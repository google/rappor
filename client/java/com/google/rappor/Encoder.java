package com.google.rappor;

import com.google.common.base.Verify;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;

import javax.annotation.concurrent.GuardedBy;
import javax.crypto.Mac;
import javax.crypto.ShortBufferException;
import javax.crypto.spec.SecretKeySpec;

/**
 * Encodes reports using the RAPPOR differentially-private encoding algorithm.
 *
 */
public class Encoder {
  /**
   * A non-decreasing version number.
   *
   * <p>The version number should increase any time the Encoder has a user-visible functional change
   * to any of encoding algorithms or the interpretation of the input parameters.
   */
  public static final long VERSION = 2;

  /**
   * Minimum length required for the user secret, in bytes.
   */
  public static final int MIN_USER_SECRET_BYTES = 32;

  /**
   * Maximum number of bits in the RAPPOR-encoded report.
   *
   * <p>This is currently limited as the bits are passed in as a signed long.
   *
   * <p>This is also constrained by assuming MAX_BITS &lt;= 256, so that we can represent a Bloom
   * filter hash index in a single byte.
   */
  public static final int MAX_BITS = 63;

  /**
   * Maximum number of Bloom filter hashes used for RAPPOR-encoded strings.
   *
   * <p>This is constrained in the current implementation by requiring 1 byte from an MD5 value
   * (which is 16 bytes long) for each Bloom filter hash.
   */
  public static final int MAX_BLOOM_HASHES = 16;

  /**
   * Maximum number of cohorts supported.
   */
  public static final int MAX_COHORTS = 128;

  /**
   * First (and only) byte of HMAC messages used to generate the cohort number.
   */
  private static final byte HMAC_TYPE_COHORT = 0x00;

  /**
   * First byte of HMAC messages used to generate a pseudo-random stream for PRNGs.
   * First 32 bytes are generated with HMAC_TYPE_PRR_PRNG_INITIAL, then each subsequent 32 bytes
   * increment this number until it reaches HMAC_TYPE_PRR_PRNG_FINAL (giving a max of 256 bytes).
   */
  private static final int HMAC_TYPE_PRR_PRNG_INITIAL = 0x01;
  private static final int HMAC_TYPE_PRR_PRNG_FINAL = 0x08;

  /**
   * A unique identifier for this Encoder, represented in UTF-8.
   *
   * <p>The (userSecret, encoderId) pair identify a the logical memoization table used for RAPPOR's
   * Permanent Randomized Response stage.  Therefore, for any userSecret, each Encoder must have a
   * distinct identifier for Permanent Randomized Response to be effective.
   *
   * <p>In practice, "memoization" is achieved by generating deterministic pseudo-random bits using
   * HMAC-SHA256.  userSecret is used as the HMAC secret key, while the encoderIdBytes is prepended
   * to each message presented to the HMAC.
   */
  private final byte[] encoderIdBytes;

  /**
   * The RAPPOR "f" probability, on the range [0.0, 1.0].
   *
   * <p>This it the probability of replacing a bit from the input with a uniform random bit when
   * generating the permanent randomized response.
   *
   * <p>Setting probabilityF to 0 disables the PRR phase of RAPPOR.
   */
  public final double probabilityF;

  /**
   * The RAPPOR "p" probability, on the range [0.0, 1.0].
   *
   * <p>This is the probability of emitting a '1' bit in the instantaneous randomized response,
   * given that the corresponding bit in the permanent randomized response is '0'.
   *
   * <p>Setting probabilityP to 0.0 and probabilityQ to 1.0 disables the IRR phase of RAPPOR.
   */
  public final double probabilityP;

  /**
   * The RAPPOR "1" probability, on the range [0.0, 1.0].
   *
   * <p>This is the probability of emitting a 1 bit in the instantaneous randomized response, given
   * that the corresponding bit in the permanent randomized response is 1.
   *
   * <p>Setting probabilityP to 0.0 and probabilityQ to 1.0 disables the IRR phase of RAPPOR.
   */
  public final double probabilityQ;

  /**
   * The number of bits in the RAPPOR-encoded report.
   *
   * <p>Must satisfy 1 &lt;= numBits &lt;= MAX_BITS.
   *
   * <ul>
   * <li>For encodeOrdinal, requires 0 &lt;= ordinal &lt; numBits.
   * <li>For encodeString, uses a numBits-wide Bloom filter.
   * <li>For encodeBits, only the low-order numBits may be non-zero.
   * </ul>
   */
  public final int numBits;

  /**
   * The number of hash functions used forming the Bloom filter encoding of a string.
   *
   * <p>Must satisfy 1 &lt;= numBloomHashes &lt;= MAX_BLOOM_HASHES.
   */
  public final int numBloomHashes;

  /**
   * The number of cohorts used for cohort assignment.
   */
  public final int numCohorts;

  /**
   * The cohort this user is assigned to for Bloom filter string encoding.
   *
   * <p>This value is stable for a given (userSecret, numCohorts) pair.  Furthermore, if two
   * encoders use the same userSecret but have different numCohorts values, the cohort assignment
   * for the encoder with the smaller numCohorts value is a bitwise suffix of the cohort assignment
   * for the encoder with the larger numCohorts value.  It follows that, if you know maximum cohort
   * assignment across a set of encoders, and you know the numCohorts setting for each encoder, then
   * you can deduce the cohort assignment for each encoder by taking the bitwise-and of the max
   * cohort value and (numCohorts-1), noting that numCohorts is required to be a positive power of
   * 2.
   */
  public final int cohort;

  /**
   * A bitmask with 1 bits in all the positions where a RAPPOR-encoded report could have a 1 bit.
   *
   * <p>The bitmask has the lowest order numBits set to 1 and the rest 0.
   */
  private final long inputMask;

  /**
   * HMAC-SHA256 utility object, initialized with the userSecret as the secret key.
   *
   * <p>This object is stateful; access must be synchronized.  The reset method must be
   * called before each use.
   *
   * <p><b>HMAC message schema for avoiding input collisions</b>
   *
   * <p>We compute the HMAC of two kinds of strings:
   *
   * <ul>
   * <li> In the constructor, to generate a cohort.  Here we HMAC the string consisting of just
   * HMAC_TYPE_COHORT.
   * <li> In computePermanentRandomizedResponse, To generate PRR PRNG.  Here we HMAC a string
   * consisting of HMAC_TYPE_PRR_PRNG + encoderIdBytes + "bytes" (where "bytes" is an 8-byte
   * representation of the data being Rappor-encoded).
   * </ul>
   *
   * <p>Clearly, there can be no conflicts between these two typs of strings, because they start
   * with different TYPE constants.  There can also be no conflicts within the cohort type, because
   * there is exactly one string in that type.
   *
   * <p>Thus the only remaining fear is that two PRR PRNG strings might collide.  This can only
   * happen for two PRR PRNG input strings that are the same length.
   *
   * <p>Observe that HMAC_TYPE_PRR_PRNG is exactly one byte, and "bytes" is exactly 8 bytes.  It
   * follows that if two PRR PRNG input strings are the same length, then their encoderIdBytes must
   * also be the same length (namely, 9 bytes shorter than the full input string.)  As a result, two
   * PRR PRNG input strings will only match in the case that they are derived from identical
   * encoderIdBytes and "bytes" strings -- which is exactly the desired behavior.
   */
  @GuardedBy("this")
  private final Mac hmacSha256;

  /**
   * MD5 utility class instance.
   *
   * <p>This object is stateful; access must be synchronized.  The reset method must be
   * called before each use.
   */
  @GuardedBy("this")
  private final MessageDigest md5;

  /**
   * A SecureRandom instance, initialized with a cryptographically secure random seed.
   */
  private final SecureRandom random;

  /**
   * Used internally for encoding longs.
   */
  @GuardedBy("this")
  private final ByteBuffer byteBuffer8;

  /**
   * Constructs a new RAPPOR message encoder.
   *
   * @param userSecret Stable secret randomly selected for this user.  UserSecret must be at least
   *     MIN_USER_SECRET_BYTES bytes of high-quality entropy.  Changing the user secret clears the
   *     memoized cohort assignments and permanent randomized responses.  Be aware that resetting
   *     these memoizations has significant privacy risks -- consult documentation at go/rappor for
   *     more details.
   * @param encoderId Uniquely identifies this encoder.  Used to differentiate momoized
   *     cohort assignments and permanent randomized responses.
   * @param numBits The number of bits in the RAPPOR-encoded report.
   * @param probabilityF The RAPPOR "f" probability, on the range [0.0, 1.0].  This will be
   *     quantized to the nearest 1/128.
   * @param probabilityP The RAPPOR "p" probability, on the range [0.0, 1.0].
   * @param probabilityQ The RAPPOR "1" probability, on the range [0.0, 1.0].
   * @param numCohorts Number of cohorts into which the user pool is randomly segmented.
   * @param numBloomHashes The number of hash functions used forming the Bloom filter encoding of a
   *     string.
   */
  public Encoder(byte[] userSecret, String encoderId, int numBits,
                 double probabilityF, double probabilityP, double probabilityQ,
                 int numCohorts, int numBloomHashes) {
    this(null,  // random
         null,  // hmacSha256,
         null,  // md5,
         userSecret, encoderId, numBits, probabilityF, probabilityP, probabilityQ, numCohorts,
         numBloomHashes);
  }

  /**
   * Constructs a new RAPPOR message encoder, using constructor-style dependency injection.
   *
   * @param random A cryptographically secure random number generator, or null (in which case a
   *     new SecureRandom will be constructed).
   * @param hmacSha256 A configured HMAC-SHA256 Mac algorithm, or null (in which case a new
   *     MAC will be constructed).  Note: Mac objects are stateful, and that state must not be
   *     modified while calls to the Encoder are active.
   * @param md5 A configured MD5 hash algorithm, or null (in which case a new MessageDigest will be
   *     constructed).   Note: MessageDigest objects are stateful, and that state must not be
   *     modified while calls to the Encoder are active.
   * @param userSecret Stable secret randomly selected for this user.  UserSecret must be at least
   *     32 bytes of high-quality entropy.  Changing the user secret clears the memoized cohort
   *     assignments and permanent randomized responses.  Be aware that resetting these memoizations
   *     has significant privacy risks -- consult documentation at go/rappor for more details.
   * @param encoderId Uniquely identifies this encoder.  Used to differentiate momoized
   *     cohort assignments and permanent randomized responses.
   * @param numBits The number of bits in the RAPPOR-encoded report.
   * @param probabilityF The RAPPOR "f" probability, on the range [0.0, 1.0].  This will be
   *     quantized to the nearest 1/128.
   * @param probabilityP The RAPPOR "p" probability, on the range [0.0, 1.0].
   * @param probabilityQ The RAPPOR "1" probability, on the range [0.0, 1.0].
   * @param numCohorts Number of cohorts into which the user pool is randomly segmented.
   * @param numBloomHashes The number of hash functions used forming the Bloom filter encoding of a
   *     string.
   */
  public Encoder(SecureRandom random, Mac hmacSha256, MessageDigest md5,
                 byte[] userSecret, String encoderId, int numBits,
                 double probabilityF, double probabilityP, double probabilityQ,
                 int numCohorts, int numBloomHashes) {
    if (md5 != null) {
      this.md5 = md5;
    } else {
      try {
        this.md5 = MessageDigest.getInstance("MD5");
      } catch (NoSuchAlgorithmException e) {
        // This should never happen.  Every implementation of the Java platform
        // is required to support MD5.
        throw new RuntimeException(e);
      }
    }

    this.md5.reset();
    this.encoderIdBytes = encoderId.getBytes(StandardCharsets.UTF_8);

    if (random != null) {
      this.random = random;
    } else {
      this.random = new SecureRandom();
    }

    if (userSecret.length < 32) {
      throw new IllegalArgumentException(
          "userSecret must be at least 32 bytes of high-quality entropy.");
    }

    if (hmacSha256 != null) {
      this.hmacSha256 = hmacSha256;
    } else {
      try {
        this.hmacSha256 = Mac.getInstance("HmacSHA256");
      } catch (NoSuchAlgorithmException e) {
        // This should never happen.  Every implementation of the Java platform
        // is required to support HmacSHA256.
        throw new RuntimeException(e);
      }
    }
    try {
      SecretKeySpec hmacKey = new SecretKeySpec(userSecret, "HmacSHA256");
      this.hmacSha256.init(hmacKey);
    } catch (InvalidKeyException e) {
      // This should never happen.  HmacSHA256 is expected to work with arbitrary
      // key strings.
      throw new RuntimeException(e);
    }

    if (probabilityF < 0 || probabilityF > 1) {
      throw new IllegalArgumentException("probabilityF must be on range [0.0, 1.0]");
    }
    this.probabilityF = Math.round(probabilityF * 128) / 128.0;

    if (probabilityP < 0 || probabilityP > 1) {
      throw new IllegalArgumentException("probabilityP must be on range [0.0, 1.0]");
    }
    this.probabilityP = probabilityP;

    if (probabilityQ < 0 || probabilityQ > 1) {
      throw new IllegalArgumentException("probabilityQ must be on range [0.0, 1.0]");
    }
    this.probabilityQ = probabilityQ;

    if (numBits < 1 || numBits > MAX_BITS) {
      throw new IllegalArgumentException("numBits must be on range [1, " + MAX_BITS + "].");
    }
    this.numBits = numBits;
    // Make a bitmask with the lowest-order numBits set to 1.
    this.inputMask = (1L << numBits) - 1;

    if (numBloomHashes < 1 || numBloomHashes > numBits) {
      throw new IllegalArgumentException("numBloomHashes must be on range [1, numBits).");
    }
    this.numBloomHashes = numBloomHashes;

    if (numCohorts < 1 || numCohorts > MAX_COHORTS) {
      throw new IllegalArgumentException("numCohorts must be on range [1, " + MAX_COHORTS + "].");
    }
    // Assuming numCohorts >= 1:
    //
    // If numCohorts is a power of 2, then numCohorts has one bit set and numCohorts - 1 has only
    // the bits to the right of numCohorts's bit set.  The bitwise-and of these is 0.
    //
    // If numCohorts is not a power of 2, then numCohorts has at least two bits set.  It follows
    // subtracting one from numCohorts keeps the most significant bit set to 1, and thus the
    // bitwise-and has at least this non-zero bit.
    final boolean numCohortsIsPowerOfTwo = (numCohorts & (numCohorts - 1)) == 0;
    if (!numCohortsIsPowerOfTwo) {
      throw new IllegalArgumentException("numCohorts must be a power of 2.");
    }
    this.numCohorts = numCohorts;

    this.hmacSha256.reset();
    this.hmacSha256.update(HMAC_TYPE_COHORT);
    ByteBuffer cohortPseudorandomStream = ByteBuffer.wrap(this.hmacSha256.doFinal());
    // cohortMasterAssignment depends only on the userSecret.
    final int cohortMasterAssignment = Math.abs(cohortPseudorandomStream.getInt()) % MAX_COHORTS;
    this.cohort = cohortMasterAssignment & (numCohorts - 1);

    // Make sure that the byte buffer has enough space for the data.
    Verify.verify(MAX_BITS <= 8 * 8); // 8 bits per byte, allocating an 8 byte buffer.
    this.byteBuffer8 = ByteBuffer.allocate(8);
  }

  /**
   * Encodes a boolean into a RAPPOR report.
   *
   * <p>The boolean is 0 or 1, then encoded using permanent and instantaneous randomized response.
   *
   * <p>In most cases, numBits should be 1 when using this method.
   */
  public long encodeBoolean(boolean bool) {
    return encodeBits(bool ? 1 : 0);
  }

  /**
   * Encodes an ordinal into a RAPPOR report.
   *
   * <p>The ordinal is represented using a 1-hot binary representation, then encoded using permanent
   * and instantaneous randomized response.
   *
   * @param ordinal A value on the range [0, numBits).
   */
  public long encodeOrdinal(int ordinal) {
    if (ordinal < 0 || ordinal >= numBits) {
      throw new IllegalArgumentException("Ordinal value must be in range [0, numBits).");
    }

    return encodeBits(1L << ordinal);
  }

  /**
   * Encodes a string into a RAPPOR report.
   *
   * <p>The string is represented using a Bloom filter with numBloomHashes hash functions, then
   * encoded using permanent and instantaneous randomized response.
   *
   * @param string An arbitrary string.
   */
  public long encodeString(String string) {
    // Implements a Bloom filter by slicing a single MD5 hash into numBloomHashes bit indices.
    final byte[] stringInUtf8 = string.getBytes(StandardCharsets.UTF_8);
    final byte[] message =
        ByteBuffer.allocate(4 + stringInUtf8.length)
                  .putInt(cohort)
                  .put(stringInUtf8)
                  .array();

    final byte[] digest;
    synchronized (this) {
      md5.reset();
      digest = md5.digest(message);
    }
    Verify.verify(digest.length == 16);
    Verify.verify(numBloomHashes <= digest.length);

    long bloomBits = 0;
    for (int i = 0; i < numBloomHashes; i++) {
      int digestByte = digest[i] & 0xFF;  // Anding with 0xFF converts signed byte to unsigned int.
      int chosenBit = digestByte % numBits;
      bloomBits |= (1L << chosenBit);
    }

    return encodeBits(bloomBits);
  }

  /**
   * Encodes an arbitrary bitstring into a RAPPOR report.
   *
   * @param bits A bitstring in which only the least significant numBits bits may be 1.
   */
  public long encodeBits(long bits) {
    final long permanentRandomizedResponse = computePermanentRandomizedResponse(bits);
    return computeInstantaneousRandomizedResponse(permanentRandomizedResponse);
  }

  /**
   * Returns the permanent randomized response for the given bits.
   *
   * <p>The response for a particular bits input is guaranteed to always be the same for any encoder
   * constructed with the same parameters (including the encoderId and the userSecret).
   */
  protected long computePermanentRandomizedResponse(long bits) {
    // Ensures that the input only has bits set in the lowest
    if ((bits & ~inputMask) != 0) {
      throw new IllegalArgumentException("Input bits had bits set past Encoder's numBits limit.");
    }

    if (probabilityF == 0.0) {
      return bits;
    }
    final byte[] pseudorandomStream = getPseudorandomStream(bits, numBits);
    Verify.verify(numBits <= pseudorandomStream.length);

    final int probabilityFTimes128 = (int) Math.round(probabilityF * 128);
    long shouldUseNoiseMask = 0;
    long noiseBits = 0;
    for (int i = 0; i < numBits; i++) {
      // Grabs a single byte from the pseudorandom stream.
      // Anding with 0xFF converts a signed byte to an unsigned integer.
      final int pseudorandomByte = pseudorandomStream[i] & 0xFF;

      // Uses bit 0 as a flip of a fair coin.
      final long noiseBit = pseudorandomByte & 0x01;
      noiseBits |= noiseBit << i;

      // Uses bits 1-7 to get a random number between 0 and 127.
      final int uniform0to127 = pseudorandomByte >> 1;
      final long shouldUseNoiseBit = uniform0to127 < probabilityFTimes128 ? 1 : 0;
      shouldUseNoiseMask |= shouldUseNoiseBit << i;
    }

    return (bits & ~shouldUseNoiseMask) | (noiseBits & shouldUseNoiseMask);
  }

  /**
   * Get a pseudorandom byte sequence that is at least length bytes (it may be more.)
   *
   * <p> We use the HMAC-SHA256 code to generate a stable pseudorandom bitstream -- that is,
   * every time we see the same combination of (seed, userSecret, encoderId, bits), we'll use the
   * same pseudorandom bitstream. This effectively implements the memoization required for the
   * permanent randomized response phase of RAPPOR.
   *
   * @param bits A bitstring used to seed the psuedo random stream.
   * @param length required length (in bytes) of psuedo random stream.
   * @return the psuedorandom stream used to determine the permanent randomized response.
   */
  byte[] getPseudorandomStream(long bits, int length) {
    final int numHMACsRequired = (int) Math.ceil(length / 32.0);
    final int numHMACsAvailable = HMAC_TYPE_PRR_PRNG_FINAL - HMAC_TYPE_PRR_PRNG_INITIAL + 1;
    Verify.verify(numHMACsRequired > 0 && numHMACsRequired <= numHMACsAvailable);

    byte[] result = new byte[numHMACsRequired * 32];
    // Each pass through the loop adds 32 bytes to the pseudorandom stream.
    for (int hmacIndex = 0; hmacIndex < numHMACsRequired; hmacIndex++) {
      final byte hmacSeed = (byte) (HMAC_TYPE_PRR_PRNG_INITIAL + hmacIndex);
      synchronized (this) {
        byteBuffer8.clear();  // Note: resets buffer indices, doesn't actually clear data.
        byteBuffer8.putLong(bits);
        byteBuffer8.flip();
        hmacSha256.reset();
        hmacSha256.update(hmacSeed);
        hmacSha256.update(encoderIdBytes);
        hmacSha256.update(byteBuffer8);
        try {
          hmacSha256.doFinal(result, hmacIndex * 32);
        } catch (ShortBufferException e) {
          throw new RuntimeException("Buffer size mismatch", e);
        }
      }
    }
    return result;
  }

  /**
   * Returns the instantaneous randomized response for the given bits.
   *
   * <p>The instantaneous response is NOT memoized -- it is sampled randomly on
   * every invocation.
   */
  protected long computeInstantaneousRandomizedResponse(long bits) {
    if ((bits & ~inputMask) != 0) {
      throw new IllegalArgumentException("Input bits had bits set past Encoder's numBits limit.");
    }

    if (probabilityP == 0.0 && probabilityQ == 1.0) {
      return bits;
    }

    long response = 0;
    for (int i = 0; i < numBits; i++) {
      final boolean bit = (bits & (1L << i)) != 0L;
      final double probability = bit ? probabilityQ : probabilityP;
      final boolean responseBit = random.nextFloat() < probability;
      response |= (responseBit ? 1L : 0L) << i;
    }
    return response;
  }

  /**
   * @return Encoder ID as a UTF-8 formatted string.
   */
  public String getEncoderId() {
    return new String(encoderIdBytes, StandardCharsets.UTF_8);
  }
}
