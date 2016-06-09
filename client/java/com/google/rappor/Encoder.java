package com.google.rappor;

import static com.google.common.base.Preconditions.checkArgument;

import com.google.common.base.Verify;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.BitSet;

import javax.annotation.Nullable;
import javax.annotation.concurrent.GuardedBy;

/**
 * Encodes reports using the RAPPOR differentially-private encoding algorithm.
 *
 * The RAPPOR algorithm is described at go/rappor and presented in detail at go/rappor-writeup.
 *
 * @author bonawitz@google.com Keith Bonawitz
 */
// TODO(bonawitz): Make encoder and interface and make this a final class implementing it.
// We can't just make this final now because there exist tests that need to Mock it.
public class Encoder {
  /**
   * A non-decreasing version number.
   *
   * <p>The version number should increase any time the Encoder has a user-visible functional change
   * to any of encoding algorithms or the interpretation of the input parameters.
   */
  public static final long VERSION = 3;

  /**
   * Minimum length required for the user secret, in bytes.
   */
  public static final int MIN_USER_SECRET_BYTES = HmacDrbg.ENTROPY_INPUT_SIZE_BYTES;

  /**
   * Maximum number of bits in the RAPPOR-encoded report.
   *
   * Must be less than HmacDrbg.MAX_BYTES_TOTAL;
   */
  public static final int MAX_BITS = 4096;

  /**
   * Maximum number of Bloom filter hashes used for RAPPOR-encoded strings.
   *
   * <p>This is constrained in the current implementation by requiring 2 bytes from an MD5 value
   * (which is 16 bytes long) for each Bloom filter hash.
   */
  public static final int MAX_BLOOM_HASHES = 8;

  /**
   * Maximum number of cohorts supported.
   */
  public static final int MAX_COHORTS = 128;

  /**
   * First (and only) byte of HMAC_DRBG personalization strings used to generate the cohort number.
   */
  private static final byte HMAC_DRBG_TYPE_COHORT = 0x00;

  /**
   * First byte of HMAC_DRBG personalization strings used to generate the PRR response.
   */
  private static final byte HMAC_DRBG_TYPE_PRR = 0x01;

  /**
   * A unique identifier for this Encoder, represented in UTF-8.
   *
   * <p>The (userSecret, encoderId) pair identify a the logical memoization table used for RAPPOR's
   * Permanent Randomized Response stage.  Therefore, for any userSecret, each Encoder must have a
   * distinct identifier for Permanent Randomized Response to be effective.
   *
   * <p>In practice, "memoization" is achieved by generating deterministic pseudo-random bits using
   * HMAC_DRBG.  encoderIdBytes is used as part of the personalization string.
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
  private final double probabilityF;

  /**
   * The RAPPOR "p" probability, on the range [0.0, 1.0].
   *
   * <p>This is the probability of emitting a '1' bit in the instantaneous randomized response,
   * given that the corresponding bit in the permanent randomized response is '0'.
   *
   * <p>Setting probabilityP to 0.0 and probabilityQ to 1.0 disables the IRR phase of RAPPOR.
   */
  private final double probabilityP;

  /**
   * The RAPPOR "1" probability, on the range [0.0, 1.0].
   *
   * <p>This is the probability of emitting a 1 bit in the instantaneous randomized response, given
   * that the corresponding bit in the permanent randomized response is 1.
   *
   * <p>Setting probabilityP to 0.0 and probabilityQ to 1.0 disables the IRR phase of RAPPOR.
   */
  private final double probabilityQ;

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
  private final int numBits;

  /**
   * The number of hash functions used forming the Bloom filter encoding of a string.
   *
   * <p>Must satisfy 1 &lt;= numBloomHashes &lt;= MAX_BLOOM_HASHES.
   */
  private final int numBloomHashes;

  /**
   * The number of cohorts used for cohort assignment.
   */
  private final int numCohorts;

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
  private final int cohort;

  /**
   * A bitmask with 1 bits in all the positions where a RAPPOR-encoded report could have a 1 bit.
   *
   * <p>The bitmask has the lowest order numBits set to 1 and the rest 0.
   */
  private final BitSet inputMask;

  /**
   * SHA-256 utility class instance.
   *
   * <p>This object is stateful; access must be synchronized.  The reset method must be
   * called before each use.
   */
  @GuardedBy("this")
  private final MessageDigest sha256;

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
   * Entropy input for constructing HmacDrbg objects.
   */
  private final byte[] userSecret;

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
    this(
        null, // random
        null, // md5,
        null, // sha256,
        userSecret,
        encoderId,
        numBits,
        probabilityF,
        probabilityP,
        probabilityQ,
        numCohorts,
        numBloomHashes);
  }

  /**
   * Constructs a new RAPPOR message encoder, using constructor-style dependency injection.
   *
   * @param random A cryptographically secure random number generator, or null (in which case a
   *     new SecureRandom will be constructed).
   * @param md5 A configured MD5 hash algorithm, or null (in which case a new MessageDigest will be
   *     constructed).   Note: MessageDigest objects are stateful, and that state must not be
   *     modified while calls to the Encoder are active.
   * @param sha256 A configured SHA-256 hash algorithm, or null (in which case a new MessageDigest
   *     will be constructed).   Note: MessageDigest objects are stateful, and that state must not
   *     be modified while calls to the Encoder are active.
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
  public Encoder(
      @Nullable SecureRandom random,
      @Nullable MessageDigest md5,
      @Nullable MessageDigest sha256,
      byte[] userSecret,
      String encoderId,
      int numBits,
      double probabilityF,
      double probabilityP,
      double probabilityQ,
      int numCohorts,
      int numBloomHashes) {
    if (md5 != null) {
      this.md5 = md5;
    } else {
      try {
        this.md5 = MessageDigest.getInstance("MD5");
      } catch (NoSuchAlgorithmException impossible) {
        // This should never happen.  Every implementation of the Java platform
        // is required to support MD5.
        throw new AssertionError(impossible);
      }
    }
    this.md5.reset();

    if (sha256 != null) {
      this.sha256 = sha256;
    } else {
      try {
        this.sha256 = MessageDigest.getInstance("SHA-256");
      } catch (NoSuchAlgorithmException impossible) {
        // This should never happen.  Every implementation of the Java platform
        // is required to support 256.
        throw new AssertionError(impossible);
      }
    }
    this.sha256.reset();

    this.encoderIdBytes = encoderId.getBytes(StandardCharsets.UTF_8);

    if (random != null) {
      this.random = random;
    } else {
      this.random = new SecureRandom();
    }

    checkArgument(
        userSecret.length >= MIN_USER_SECRET_BYTES,
        "userSecret must be at least %s bytes of high-quality entropy.",
        MIN_USER_SECRET_BYTES);
    this.userSecret = userSecret;

    checkArgument(
        probabilityF >= 0 && probabilityF <= 1, "probabilityF must be on range [0.0, 1.0]");
    this.probabilityF = Math.round(probabilityF * 128) / 128.0;

    checkArgument(
        probabilityP >= 0 && probabilityP <= 1, "probabilityP must be on range [0.0, 1.0]");
    this.probabilityP = probabilityP;

    checkArgument(
        probabilityQ >= 0 && probabilityQ <= 1, "probabilityQ must be on range [0.0, 1.0]");
    this.probabilityQ = probabilityQ;

    checkArgument(
        numBits >= 1 && numBits <= MAX_BITS, "numBits must be on range [1, " + MAX_BITS + "].");
    this.numBits = numBits;
    // Make a bitmask with the lowest-order numBits set to 1.
    this.inputMask = new BitSet(numBits);
    this.inputMask.set(0, numBits, true);

    checkArgument(
        numBloomHashes >= 1 && numBloomHashes <= numBits,
        "numBloomHashes must be on range [1, numBits).");
    this.numBloomHashes = numBloomHashes;

    checkArgument(
        numCohorts >= 1 && numCohorts <= MAX_COHORTS,
        "numCohorts must be on range [1, " + MAX_COHORTS + "].");

    // Assuming numCohorts >= 1:
    //
    // If numCohorts is a power of 2, then numCohorts has one bit set and numCohorts - 1 has only
    // the bits to the right of numCohorts's bit set.  The bitwise-and of these is 0.
    //
    // If numCohorts is not a power of 2, then numCohorts has at least two bits set.  It follows
    // subtracting one from numCohorts keeps the most significant bit set to 1, and thus the
    // bitwise-and has at least this non-zero bit.
    boolean numCohortsIsPowerOfTwo = (numCohorts & (numCohorts - 1)) == 0;
    checkArgument(numCohortsIsPowerOfTwo, "numCohorts must be a power of 2.");
    this.numCohorts = numCohorts;

    // cohortMasterAssignment depends only on the userSecret.
    HmacDrbg cohortDrbg = new HmacDrbg(userSecret, new byte[] {HMAC_DRBG_TYPE_COHORT});
    ByteBuffer cohortDrbgBytes = ByteBuffer.wrap(cohortDrbg.nextBytes(4));
    int cohortMasterAssignment = Math.abs(cohortDrbgBytes.getInt()) % MAX_COHORTS;
    this.cohort = cohortMasterAssignment & (numCohorts - 1);
  }

  public double getProbabilityF() {
    return probabilityF;
  }

  public double getProbabilityP() {
    return probabilityP;
  }

  public double getProbabilityQ() {
    return probabilityQ;
  }

  public int getNumBits() {
    return numBits;
  }

  public int getNumBloomHashes() {
    return numBloomHashes;
  }

  public int getNumCohorts() {
    return numCohorts;
  }

  public int getCohort() {
    return cohort;
  }

  /**
   * Returns the Encoder ID as a UTF-8 formatted string.
   */
  public String getEncoderId() {
    return new String(encoderIdBytes, StandardCharsets.UTF_8);
  }

  /**
   * Encodes a boolean into a RAPPOR report.
   *
   * <p>The boolean is 0 or 1, then encoded using permanent and instantaneous randomized response.
   *
   * <p>In most cases, numBits should be 1 when using this method.
   */
  public byte[] encodeBoolean(boolean bool) {
    BitSet input = new BitSet(numBits);
    input.set(0, bool);
    return encodeBits(input);
  }

  /**
   * Encodes an ordinal into a RAPPOR report.
   *
   * <p>The ordinal is represented using a 1-hot binary representation, then encoded using permanent
   * and instantaneous randomized response.
   *
   * @param ordinal A value on the range [0, numBits).
   */
  public byte[] encodeOrdinal(int ordinal) {
    checkArgument(
        ordinal >= 0 && ordinal < numBits, "Ordinal value must be in range [0, numBits).");
    BitSet input = new BitSet(numBits);
    input.set(ordinal, true);
    return encodeBits(input);
  }

  /**
   * Encodes a string into a RAPPOR report.
   *
   * <p>The string is represented using a Bloom filter with numBloomHashes hash functions, then
   * encoded using permanent and instantaneous randomized response.
   *
   * @param string An arbitrary string.
   */
  public byte[] encodeString(String string) {
    // Implements a Bloom filter by slicing a single MD5 hash into numBloomHashes bit indices.
    byte[] stringInUtf8 = string.getBytes(StandardCharsets.UTF_8);
    byte[] message =
        ByteBuffer.allocate(4 + stringInUtf8.length)
                  .putInt(cohort)
                  .put(stringInUtf8)
                  .array();

    byte[] digest;
    synchronized (this) {
      md5.reset();
      digest = md5.digest(message);
    }
    Verify.verify(digest.length == 16);
    Verify.verify(numBloomHashes <= digest.length / 2);

    BitSet input = new BitSet(numBits);
    for (int i = 0; i < numBloomHashes; i++) {
      // Convert byte pairs to ints on [0, 65535].
      // Anding with 0xFF converts signed byte to unsigned int.
      int digestWord = (digest[i * 2] & 0xFF) * 256 + (digest[i * 2 + 1] & 0xFF);
      int chosenBit = digestWord % numBits;
      input.set(chosenBit, true);
    }

    return encodeBits(input);
  }

  /**
   * Encodes an arbitrary bitstring into a RAPPOR report.
   *
   * @param bits A bitstring in which only the least significant numBits bits may be 1.
   */
  public byte[] encodeBits(byte[] bits) {
    return encodeBits(BitSet.valueOf(bits));
  }

  /**
   * Encodes an arbitrary bitstring into a RAPPOR report.
   *
   * @param bits A bitstring in which only the least significant numBits bits may be 1.
   */
  private byte[] encodeBits(BitSet bits) {
    BitSet permanentRandomizedResponse = computePermanentRandomizedResponse(bits);
    BitSet encodedBitSet = computeInstantaneousRandomizedResponse(permanentRandomizedResponse);

    // BitSet.toByteArray only returns enough bytes to capture the most significant bit
    // that is set.  For example, a BitSet with no bits set could return a length-0 array.
    // In contrast, we guarantee that our output is sized according to numBits.
    byte[] encodedBytes = encodedBitSet.toByteArray();
    byte[] output = new byte[(numBits + 7) / 8];
    Verify.verify(encodedBytes.length <= output.length);
    System.arraycopy(
        encodedBytes, // src
        0, // srcPos
        output, // dest
        0, // destPos
        encodedBytes.length); // length
    return output;
  }

  /**
   * Returns the permanent randomized response for the given bits.
   *
   * <p>The response for a particular bits input is guaranteed to always be the same for any encoder
   * constructed with the same parameters (including the encoderId and the userSecret).
   */
  private BitSet computePermanentRandomizedResponse(BitSet bits) {
    // Ensures that the input only has bits set in the lowest
    BitSet masked = new BitSet();
    masked.or(bits);
    masked.andNot(inputMask);
    checkArgument(masked.isEmpty(), "Input bits had bits set past Encoder's numBits limit.");

    if (probabilityF == 0.0) {
      return bits;
    }

    // Builds a personalization string that contains both the encoderId and input value (bits),
    // and is no longer than HmacDrbg.MAX_PERSONALIZATION_STRING_LENGTH_BYTES.  The first byte
    // of the personalization string is always HMAC_DRBG_TYPE_PRR, to avoid collisions with the
    // cohort-generation personalization string.
    byte[] personalizationString;
    synchronized (this) {
      int personalizationStringLength =
          Math.min(HmacDrbg.MAX_PERSONALIZATION_STRING_LENGTH_BYTES, 1 + sha256.getDigestLength());
      personalizationString = new byte[personalizationStringLength];
      personalizationString[0] = HMAC_DRBG_TYPE_PRR;
      sha256.reset();
      sha256.update(encoderIdBytes);
      sha256.update(new byte[] {0});
      sha256.update(bits.toByteArray());
      byte[] digest = sha256.digest(personalizationString);
      System.arraycopy(digest, 0, personalizationString, 1, personalizationString.length - 1);
    }

    HmacDrbg drbg = new HmacDrbg(userSecret, personalizationString);
    byte[] pseudorandomStream = drbg.nextBytes(numBits);
    Verify.verify(numBits <= pseudorandomStream.length);

    int probabilityFTimes128 = (int) Math.round(probabilityF * 128);
    BitSet result = new BitSet(numBits);
    for (int i = 0; i < numBits; i++) {
      // Grabs a single byte from the pseudorandom stream.
      // Anding with 0xFF converts a signed byte to an unsigned integer.
      int pseudorandomByte = pseudorandomStream[i] & 0xFF;

      // Uses bits 1-7 to get a random number between 0 and 127.
      int uniform0to127 = pseudorandomByte >> 1;
      boolean shouldUseNoise = uniform0to127 < probabilityFTimes128;

      if (shouldUseNoise) {
        // Uses bit 0 as a flip of a fair coin.
        result.set(i, (pseudorandomByte & 0x01) > 0);
      } else {
        result.set(i, bits.get(i));
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
  private BitSet computeInstantaneousRandomizedResponse(BitSet bits) {
    // Ensures that the input only has bits set in the lowest
    BitSet masked = new BitSet();
    masked.or(bits);
    masked.andNot(inputMask);
    checkArgument(masked.isEmpty(), "Input bits had bits set past Encoder's numBits limit.");

    if (probabilityP == 0.0 && probabilityQ == 1.0) {
      return bits;
    }

    BitSet response = new BitSet(numBits);
    for (int i = 0; i < numBits; i++) {
      boolean bit = bits.get(i);
      double probability = bit ? probabilityQ : probabilityP;
      boolean responseBit = random.nextFloat() < probability;
      response.set(i, responseBit);
    }
    return response;
  }
}
