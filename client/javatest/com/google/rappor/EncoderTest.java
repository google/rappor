package com.google.rappor;

import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.not;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertThat;
import static org.junit.Assert.fail;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.junit.runners.BlockJUnit4ClassRunner;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;

/**
 * Unit tests for {@link Encoder}.
 */
@RunWith(BlockJUnit4ClassRunner.class)
public class EncoderTest {
  
  /**
   * Convert a human readable string to a 32 byte userSecret for testing.
   *
   * <p>Do not use this in a production environment!  For security, userSecret
   * must be at least 32 bytes of high-quality entropy.
   */
  private static byte[] makeTestingUserSecret(String testingSecret) {
    // We generate the fake user secret by concatenating two copies of the
    // 16 byte MD5 hash of the testingSecret string encoded in UTF 8.
    final MessageDigest md5;
    try {
      md5 = MessageDigest.getInstance("MD5");
    } catch (NoSuchAlgorithmException e) {
      // This should never happen.  Every implementation of the Java platform
      // is required to support MD5.
      throw new RuntimeException(e);
    }
    final byte[] digest = md5.digest(testingSecret.getBytes(StandardCharsets.UTF_8));
    assertEquals(16, digest.length);
    return ByteBuffer.allocate(32).put(digest).put(digest).array();
  }
  
  @Test
  public void testEncoderConstruction_goodArguments()  {
    // Full RAPPOR
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                13.0 / 128.0,  // probabilityF
                0.25,  // probabilityP
                0.75,  // probabilityQ
                1,  // numCohorts
                2);  // numBloomHashes

    // IRR-only (no PRR)
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                0,  // probabilityF
                0.25,  // probabilityP
                0.75,  // probabilityQ
                1,  // numCohorts
                2);  // numBloomHashes

    // PRR-only (no IRR)
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                13.0 / 128.0,  // probabilityF
                0.0,  // probabilityP
                1.0,  // probabilityQ
                1,  // numCohorts
                2);  // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_userSecretTooShort() {
    byte[] tooShortSecret = new byte[31];
    try {
      new Encoder(tooShortSecret,  // userSecret
                  "Foo",  // encoderId
                  8,  // numBits,
                  13.0 / 128.0,  // probabilityF
                  0.25,  // probabilityP
                  0.75,  // probabilityQ
                  1,  // numCohorts
                  2);  // numBloomHashes
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }
  }

  @Test
  public void testEncoderConstruction_userSecretMayBeLong() {
    byte[] tooLongSecret = new byte[33];
    new Encoder(tooLongSecret,  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                13.0 / 128.0,  // probabilityF
                0.25,  // probabilityP
                0.75,  // probabilityQ
                1,  // numCohorts
                2);  // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_numBitsOutOfRange()  {
    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  0,  // numBits,
                  13.0 / 128.0,  // probabilityF
                  0.25,  // probabilityP
                  0.75,  // probabilityQ
                  1,  // numCohorts
                  2);  // numBloomHashes
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }

    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  64,  // numBits,
                  13.0 / 128.0,  // probabilityF
                  0.25,  // probabilityP
                  0.75,  // probabilityQ
                  1,  // numCohorts
                  2);  // numBloomHashes
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }
  }

  @Test
  public void testEncoderConstruction_probabilityFOutOfRange()  {
    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  8,  // numBits,
                  -0.01,  // probabilityF
                  0.25,  // probabilityP
                  0.75,  // probabilityQ
                  1,  // numCohorts
                  2);  // numBloomHashes
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }

    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  8,  // numBits,
                  1.01,  // probabilityF
                  0.25,  // probabilityP
                  0.75,  // probabilityQ
                  1,  // numCohorts
                  2);  // numBloomHashes
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }
  }

  @Test
  public void testEncoderConstruction_probabilityPOutOfRange()  {
    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  8,  // numBits,
                  13.0 / 128.0,  // probabilityF
                  -0.01,  // probabilityP
                  0.75,  // probabilityQ
                  1,  // numCohorts
                  2);  // numBloomHashes
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }

    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  8,  // numBits,
                  13.0 / 128.0,  // probabilityF
                  1.01,  // probabilityP
                  0.75,  // probabilityQ
                  1,  // numCohorts
                  2);  // numBloomHashes
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }
  }

  @Test
  public void testEncoderConstruction_probabilityQOutOfRange()  {
    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  8,  // numBits,
                  13.0 / 128.0,  // probabilityF
                  0.25,  // probabilityP
                  -0.01,  // probabilityQ
                  1,  // numCohorts
                  2);  // numBloomHashes
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }

    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  8,  // numBits,
                  13.0 / 128.0,  // probabilityF
                  0.75,  // probabilityP
                  1.01,  // probabilityQ
                  1,  // numCohorts
                  2);  // numBloomHashes
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }
  }

  @Test
  public void testEncoderConstruction_numCohortsOutOfRange()  {
    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  8,  // numBits,
                  13.0 / 128.0,  // probabilityF
                  0.25,  // probabilityP
                  0.75,  // probabilityQ
                  0,  // numCohorts
                  2);  // numBloomHashes
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }

    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  8,  // numBits,
                  13.0 / 128.0,  // probabilityF
                  0.25,  // probabilityP
                  0.75,  // probabilityQ
                  Encoder.MAX_COHORTS + 1,  // numCohorts
                  2);  // numBloomHashes
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }

    // numCohorts must be a power of 2.
    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  8,  // numBits,
                  13.0 / 128.0,  // probabilityF
                  0.25,  // probabilityP
                  0.75,  // probabilityQ
                  3,  // numCohorts
                  2);  // numBloomHashes
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }
  }

  @Test
  public void testEncoderConstruction_numBloomHashesOutOfRange()  {
    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  8,  // numBits,
                  13.0 / 128.0,  // probabilityF
                  0.25,  // probabilityP
                  0.75,  // probabilityQ
                  1,  // numCohorts
                  0);  // numBloomHashes
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }

    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  8,  // numBits,
                  13.0 / 128.0,  // probabilityF
                  0.25,  // probabilityP
                  0.75,  // probabilityQ
                  1,  // numCohorts
                  9);  // numBloomHashes
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }
  }

  @Test
  public void testEncoderGetCohort()  {
    // This is a stable, random cohort assignment.
    assertEquals(
        3,
        new Encoder(makeTestingUserSecret("Blotto"),  // userSecret
                    "Foo",  // encoderId
                    8,  // numBits,
                    13.0 / 128.0,  // probabilityF
                    0.25,  // probabilityP
                    0.75,  // probabilityQ
                    4,  // numCohorts
                    2)  // numBloomHashes
            .cohort);

    // With numCohorts == 1, the only possible cohort assigment is 0.
    assertEquals(
        0,
        new Encoder(makeTestingUserSecret("Blotto"),  // userSecret
                    "Foo",  // encoderId
                    8,  // numBits,
                    13.0 / 128.0,  // probabilityF
                    0.25,  // probabilityP
                    0.75,  // probabilityQ
                    1,  // numCohorts
                    2)  // numBloomHashes
            .cohort);

    // Changing the user secret changes the cohort.
    assertEquals(
        0,
        new Encoder(makeTestingUserSecret("Bar1"),  // userSecret
                    "Foo",  // encoderId
                    8,  // numBits,
                    13.0 / 128.0,  // probabilityF
                    0.25,  // probabilityP
                    0.75,  // probabilityQ
                    4,  // numCohorts
                    2)  // numBloomHashes
            .cohort);

    assertEquals(
        1,
        new Encoder(makeTestingUserSecret("Bar2"),  // userSecret
                    "Foo",  // encoderId
                    8,  // numBits,
                    13.0 / 128.0,  // probabilityF
                    0.25,  // probabilityP
                    0.75,  // probabilityQ
                    4,  // numCohorts
                    2)  // numBloomHashes
            .cohort);

    // Changing the encoder id does not changes the cohort.
    assertEquals(
        3,
        new Encoder(makeTestingUserSecret("Blotto"),  // userSecret
                    "Foo1",  // encoderId
                    8,  // numBits,
                    13.0 / 128.0,  // probabilityF
                    0.25,  // probabilityP
                    0.75,  // probabilityQ
                    4,  // numCohorts
                    2)  // numBloomHashes
            .cohort);

    assertEquals(
        3,
        new Encoder(makeTestingUserSecret("Blotto"),  // userSecret
                    "Foo2",  // encoderId
                    8,  // numBits,
                    13.0 / 128.0,  // probabilityF
                    0.25,  // probabilityP
                    0.75,  // probabilityQ
                    4,  // numCohorts
                    2)  // numBloomHashes
            .cohort);

    assertEquals(
        3,
        new Encoder(makeTestingUserSecret("Blotto"),  // userSecret
                    "Foo3",  // encoderId
                    8,  // numBits,
                    13.0 / 128.0,  // probabilityF
                    0.25,  // probabilityP
                    0.75,  // probabilityQ
                    4,  // numCohorts
                    2)  // numBloomHashes
            .cohort);

    // Cohort assignments are bit-wise subsets
    final int cohortAssignmentBig =
        new Encoder(makeTestingUserSecret("Blotto"),  // userSecret
                    "Foo",  // encoderId
                    8,  // numBits,
                    13.0 / 128.0,  // probabilityF
                    0.25,  // probabilityP
                    0.75,  // probabilityQ
                    Encoder.MAX_COHORTS,  // numCohorts
                    2)  // numBloomHashes
            .cohort;

    final int numCohortsSmall = Encoder.MAX_COHORTS / 2;
    // Verify that numCohortsSmall is a power of 2.
    assertEquals(0, numCohortsSmall & (numCohortsSmall - 1));
    final int cohortAssignmentSmall =
        new Encoder(makeTestingUserSecret("Blotto"),  // userSecret
                    "Foo",  // encoderId
                    8,  // numBits,
                    13.0 / 128.0,  // probabilityF
                    0.25,  // probabilityP
                    0.75,  // probabilityQ
                    numCohortsSmall,  // numCohorts
                    2)  // numBloomHashes
            .cohort;

    // This validates that the test case is well chosen.  If it fails, select a different userSecret
    // or encoderId.
    assertNotEquals(cohortAssignmentBig, cohortAssignmentSmall);

    // Test that cohortAssignmentSmall is a suffix of cohortAssignmentBig when represented in
    // binary.
    assertEquals(cohortAssignmentBig & (numCohortsSmall - 1), cohortAssignmentSmall);
  }

  @Test
  public void testEncoderEncodeBits_identity()  {
    assertEquals(
        0b11111101L,
        new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                    "Foo",  // encoderId
                    8,  // numBits,
                    0,  // probabilityF
                    0,  // probabilityP
                    1,  // probabilityQ
                    1,  // numCohorts
                    2)  // numBloomHashes
            .encodeBits(0b11111101L));

    assertEquals(
        0xD56B8119L,
        new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                    "Foo",  // encoderId
                    32,  // numBits,
                    0,  // probabilityF
                    0,  // probabilityP
                    1,  // probabilityQ
                    1,  // numCohorts
                    2)  // numBloomHashes
            .encodeBits(0xD56B8119L));
  }

  @Test
  public void testEncoderEncodeBits_outOfRange()  {
    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  8,  // numBits,
                  0,  // probabilityF
                  0,  // probabilityP
                  1,  // probabilityQ
                  1,  // numCohorts
                  2)  // numBloomHashes
          .encodeBits(0x100);  // 9 bits
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }
  }

  @Test
  public void testEncoderEncodeBoolean_identity()  {
    assertEquals(
        0x1L,
        new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                    "Foo",  // encoderId
                    1,  // numBits,
                    0,  // probabilityF
                    0,  // probabilityP
                    1,  // probabilityQ
                    1,  // numCohorts
                    1)  // numBloomHashes
            .encodeBoolean(true));

    assertEquals(
        0x0L,
        new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                    "Foo",  // encoderId
                    1,  // numBits,
                    0,  // probabilityF
                    0,  // probabilityP
                    1,  // probabilityQ
                    1,  // numCohorts
                    1)  // numBloomHashes
            .encodeBoolean(false));
  }

  @Test
  public void testEncoderEncodeOrdinal_identity()  {
    assertEquals(
        0b000000000001L,
        new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                    "Foo",  // encoderId
                    12,  // numBits,
                    0,  // probabilityF
                    0,  // probabilityP
                    1,  // probabilityQ
                    1,  // numCohorts
                    1)  // numBloomHashes
            .encodeOrdinal(0));

    assertEquals(
        0b100000000000L,
        new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                    "Foo",  // encoderId
                    12,  // numBits,
                    0,  // probabilityF
                    0,  // probabilityP
                    1,  // probabilityQ
                    1,  // numCohorts
                    1)  // numBloomHashes
            .encodeOrdinal(11));
  }

  @Test
  public void testEncoderEncodeOrdinal_outOfRange()  {
    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  12,  // numBits,
                  0,  // probabilityF
                  0,  // probabilityP
                  1,  // probabilityQ
                  1,  // numCohorts
                  1)  // numBloomHashes
          .encodeOrdinal(-1);
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }

    try {
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  12,  // numBits,
                  0,  // probabilityF
                  0,  // probabilityP
                  1,  // probabilityQ
                  1,  // numCohorts
                  1)  // numBloomHashes
          .encodeOrdinal(12);
      fail();  // COV_NF_LINE
    } catch (IllegalArgumentException expected) {
    }
  }

  @Test
  public void testEncoderEncodeString_identity()  {
    assertEquals(
        0b100100000000L,
        new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                    "Foo",  // encoderId
                    12,  // numBits,
                    0,  // probabilityF
                    0,  // probabilityP
                    1,  // probabilityQ
                    1,  // numCohorts (so must be cohort 0)
                    2)  // numBloomHashes
            .encodeString("Whizbang"));

    // Changing the user but keeping the cohort the same (both cohort 0)
    // results in the same encoding.
    assertEquals(
        0b100100000000L,
        new Encoder(makeTestingUserSecret("Blotto"),  // userSecret
                    "Foo",  // encoderId
                    12,  // numBits,
                    0,  // probabilityF
                    0,  // probabilityP
                    1,  // probabilityQ
                    1,  // numCohorts (so must be cohort 0)
                    2)  // numBloomHashes
            .encodeString("Whizbang"));

    // When the user is in a different cohort, she gets a different encoding.
    Encoder cohortProbeEncoder =
      new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                  "Foo",  // encoderId
                  12,  // numBits,
                  0,  // probabilityF
                  0,  // probabilityP
                  1,  // probabilityQ
                  4,  // numCohorts
                  2);  // numBloomHashes
    assertEquals(3, cohortProbeEncoder.cohort);
    assertEquals(
        0b010000100000L,
        cohortProbeEncoder.encodeString("Whizbang"));

    // Changing the string gets a different encoding.
    assertEquals(
        0b001001000000L,
        new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                    "Foo",  // encoderId
                    12,  // numBits,
                    0,  // probabilityF
                    0,  // probabilityP
                    1,  // probabilityQ
                    1,  // numCohorts (so must be cohort 0)
                    2)  // numBloomHashes
            .encodeString("Xyzzy"));

    assertEquals(
        0b000000000010L,
        new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                    "Foo",  // encoderId
                    12,  // numBits,
                    0,  // probabilityF
                    0,  // probabilityP
                    1,  // probabilityQ
                    1,  // numCohorts (so must be cohort 0)
                    2)  // numBloomHashes
            .encodeString("Thud"));
  }

  @Test
  public void testEncoderGetPseudorandomStream() {
     Encoder encoder = new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                                   "Foo",  // encoderId
                                   8,  // numBits,
                                   0.25,  // probabilityF
                                   0,  // probabilityP
                                   1,  // probabilityQ
                                   1,  // numCohorts
                                   2);  // numBloomHashes
    final byte[] pseudorandomStream1 = encoder.getPseudorandomStream(1L, 8);
    final byte[] pseudorandomStream2 = encoder.getPseudorandomStream(2L, 8);
    assertThat(pseudorandomStream1, not(equalTo(pseudorandomStream2)));
  }

  @Test
  public void testEncoderEncodeBits_prrMemoizes()  {
    assertEquals(
        0b10011101L,
        new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                    "Foo",  // encoderId
                    8,  // numBits,
                    0.25,  // probabilityF
                    0,  // probabilityP
                    1,  // probabilityQ
                    1,  // numCohorts
                    2)  // numBloomHashes
            .encodeBits(0b11111101L));

    assertEquals(
        0b11110101L,
        new Encoder(makeTestingUserSecret("Baz"),  // userSecret
                    "Foo",  // encoderId
                    8,  // numBits,
                    0.25,  // probabilityF
                    0,  // probabilityP
                    1,  // probabilityQ
                    1,  // numCohorts
                    2)  // numBloomHashes
            .encodeBits(0b11111101L));
  }

  @Test
  public void testEncoderEncodeBits_prrFlipProbability() {
    final int numSamples = 10000;
    final int numBits = 8;
    final double probabilityF = 1.0 / 32.0;
    final long inputValue = 0b11111101L;

    int counts[] = new int[64];
    for (int iSample = 0; iSample < numSamples; iSample++) {
      Encoder encoder =
          new Encoder(makeTestingUserSecret("User" + iSample),  // userSecret
                      "Foo",  // encoderId
                      numBits,  // numBits,
                      probabilityF,  // probabilityF
                      0,  // probabilityP
                      1,  // probabilityQ
                      1,  // numCohorts
                      2);  // numBloomHashes
      final long encoded = encoder.encodeBits(inputValue);
      assertEquals(
        encoded, encoder.encodeBits(inputValue));

      for (int iBit = 0; iBit < numBits; iBit++) {
        if ((encoded & (1L << iBit)) != 0) {
          counts[iBit]++;
        }
      }
    }

    assertEquals(9835, counts[0]);  // input = 1, expectation = 9843.75
    assertEquals(145, counts[1]);  // input = 0, expectation = 156.25
    assertEquals(9853, counts[2]);  // input = 1, expectation = 9843.75
    assertEquals(9849, counts[3]);  // input = 1, expectation = 9843.75
    assertEquals(9842, counts[4]);  // input = 1, expectation = 9843.75
    assertEquals(9858, counts[5]);  // input = 1, expectation = 9843.75
    assertEquals(9833, counts[6]);  // input = 1, expectation = 9843.75
    assertEquals(9852, counts[7]);  // input = 1, expectation = 9843.75

    // Check that no high-order bit past numBits ever got set.
    for (int iBit = numBits; iBit < 64; iBit++) {
      assertEquals(0, counts[iBit]);
    }
  }

  @Test
  public void testEncoderEncodeBits_irrFlipProbability() throws NoSuchAlgorithmException {
    final int numBits = 8;
    final double probabilityP = 0.25;
    final double probabilityQ = 0.85;
    final long inputValue = 0b11111101L;

    final SecureRandom random = SecureRandom.getInstance("SHA1PRNG");
    random.setSeed(0x12345678L);

    int counts[] = new int[64];
    for (int iSample = 0; iSample < 10000; iSample++) {
      Encoder encoder =
          new Encoder(random,
                      null,  // hmacSha256
                      null,  // md5
                      makeTestingUserSecret("User" + iSample),  // userSecret
                      "Foo",  // encoderId
                      numBits,  // numBits,
                      0,  // probabilityF
                      probabilityP,  // probabilityP
                      probabilityQ,  // probabilityQ
                      1,  // numCohorts
                      2);  // numBloomHashes
      final long encoded = encoder.encodeBits(inputValue);

      for (int iBit = 0; iBit < numBits; iBit++) {
        if ((encoded & (1L << iBit)) != 0) {
          counts[iBit]++;
        }
      }
    }

    assertEquals(8481, counts[0]);  // input = 1, 99.99% CI = [8358, 8636]
    assertEquals(2477, counts[1]);  // input = 0, 99.99% CI = [2332, 2669]
    assertEquals(8486, counts[2]);  // input = 1, 99.99% CI = [8358, 8636]
    assertEquals(8495, counts[3]);  // input = 1, 99.99% CI = [8358, 8636]
    assertEquals(8563, counts[4]);  // input = 1, 99.99% CI = [8358, 8636]
    assertEquals(8560, counts[5]);  // input = 1, 99.99% CI = [8358, 8636]
    assertEquals(8481, counts[6]);  // input = 1, 99.99% CI = [8358, 8636]
    assertEquals(8491, counts[7]);  // input = 1, 99.99% CI = [8358, 8636]

    // Check that no high-order bit past numBits ever got set.
    for (int iBit = numBits; iBit < 64; iBit++) {
      assertEquals(0, counts[iBit]);
    }
  }

  @Test
  public void testEncoderEncodeBits_endToEnd() throws NoSuchAlgorithmException {
    final int numBits = 8;

    final long inputValue = 0b11111101L;
    final long prrValue = 0b10011101L;
    final long prrAndIrrValue = 0b10011110L;

    // Verify that PRR is working as expected.
    assertEquals(
        prrValue,
        new Encoder(null,
                    null,  // hmacSha256
                    null,  // md5
                    makeTestingUserSecret("Bar"),  // userSecret
                    "Foo",  // encoderId
                    numBits,  // numBits,
                    0.25,  // probabilityF
                    0,  // probabilityP
                    1,  // probabilityQ
                    1,  // numCohorts
                    2)  // numBloomHashes
            .encodeBits(inputValue));

    // Verify that IRR is working as expected.
    final SecureRandom random1 = SecureRandom.getInstance("SHA1PRNG");
    random1.setSeed(0x12345678L);
    assertEquals(
        prrAndIrrValue,
        new Encoder(random1,
                    null,  // hmacSha256
                    null,  // md5
                    makeTestingUserSecret("Bar"),  // userSecret
                    "Foo",  // encoderId
                    numBits,  // numBits,
                    0,  // probabilityF
                    0.3,  // probabilityP
                    0.7,  // probabilityQ
                    1,  // numCohorts
                    2)  // numBloomHashes
            .encodeBits(prrValue));

    // Test that end-to-end is the result of PRR + IRR.
    final SecureRandom random2 = SecureRandom.getInstance("SHA1PRNG");
    random2.setSeed(0x12345678L);
    assertEquals(
        prrAndIrrValue,
        new Encoder(random2,
                    null,  // hmacSha256
                    null,  // md5
                    makeTestingUserSecret("Bar"),  // userSecret
                    "Foo",  // encoderId
                    numBits,  // numBits,
                    0.25,  // probabilityF
                    0.3,  // probabilityP
                    0.7,  // probabilityQ
                    1,  // numCohorts
                    2)  // numBloomHashes
            .encodeBits(inputValue));
  }

  @Test
  public void testEncoderEncodeBits_32BitValuesEncodeSuccessfully()
      throws NoSuchAlgorithmException {
    // Regression test for b/22035650.
    final int numBits = 32;
    final byte[] userSecret = makeTestingUserSecret("Bar");

    // Explicitly spot-check the output for 2^0 and 2^31.
    final long inputValue0 = 1L;
    final long outputValue0 = 2737831998L;
    final SecureRandom random0 = SecureRandom.getInstance("SHA1PRNG");
    random0.setSeed(0x12345678L);
    assertEquals(
        outputValue0,
        new Encoder(random0,
                    null,  // hmacSha256
                    null,  // md5
                    userSecret,  // userSecret
                    "MyEncoder",  // encoderId
                    numBits,  // numBits,
                    0.25,  // probabilityF
                    0.3,  // probabilityP
                    0.7,  // probabilityQ
                    1,  // numCohorts
                    2)  // numBloomHashes
            .encodeBits(inputValue0));

    final long inputValue31 = 1L << 31;
    final long outputValue31 = 3006267478L;
    final SecureRandom random31 = SecureRandom.getInstance("SHA1PRNG");
    random31.setSeed(0x12345678L);
    assertEquals(
        outputValue31,
        new Encoder(random31,
                    null,  // hmacSha256
                    null,  // md5
                    userSecret,  // userSecret
                    "MyEncoder",  // encoderId
                    numBits,  // numBits,
                    0.25,  // probabilityF
                    0.3,  // probabilityP
                    0.7,  // probabilityQ
                    1,  // numCohorts
                    2)  // numBloomHashes
            .encodeBits(inputValue31));

    // Check the range 2^1 to 2^30, making sure no values produce exceptions.
    final SecureRandom randomRange = SecureRandom.getInstance("SHA1PRNG");
    randomRange.setSeed(0x12345678L);
    for (int i = 1; i <= 30; i++) {
      final long inputValue = 1L << (i - 1);
      new Encoder(randomRange,
                  null,  // hmacSha256
                  null,  // md5
                  userSecret,  // userSecret
                  "MyEncoder",  // encoderId
                  numBits,  // numBits,
                  0.25,  // probabilityF
                  0.3,  // probabilityP
                  0.7,  // probabilityQ
                  1,  // numCohorts
                  2)  // numBloomHashes
          .encodeBits(inputValue);
    }
  }

  @Test
  public void testEncoderEncodeBits_63BitValuesEncodeSuccessfully()
      throws NoSuchAlgorithmException {
    final int numBits = 63;
    final byte[] userSecret = makeTestingUserSecret("Bar");

    // Explicitly spot-check the output for 2^0 and 2^63.
    final long inputValue0 = 1L;
    final long outputValue0 = 876136553316876350L;
    final SecureRandom random0 = SecureRandom.getInstance("SHA1PRNG");
    random0.setSeed(0x12345678L);
    assertEquals(
        outputValue0,
        new Encoder(random0,
            null,  // hmacSha256
            null,  // md5
            userSecret,  // userSecret
            "MyEncoder",  // encoderId
            numBits,  // numBits,
            0.25,  // probabilityF
            0.3,  // probabilityP
            0.7,  // probabilityQ
            1,  // numCohorts
            2)  // numBloomHashes
            .encodeBits(inputValue0));

    final long inputValue63 = 1L << 62;
    final long outputValue63 = 5478808775419756598L;
    final SecureRandom random63 = SecureRandom.getInstance("SHA1PRNG");
    random63.setSeed(0x12345678L);
    assertEquals(
        outputValue63,
        new Encoder(random63,
            null,  // hmacSha256
            null,  // md5
            userSecret,  // userSecret
            "MyEncoder",  // encoderId
            numBits,  // numBits,
            0.25,  // probabilityF
            0.3,  // probabilityP
            0.7,  // probabilityQ
            1,  // numCohorts
            2)  // numBloomHashes
            .encodeBits(inputValue63));

    // Check the range 2^1 to 2^62, making sure no values produce exceptions.
    final SecureRandom randomRange = SecureRandom.getInstance("SHA1PRNG");
    randomRange.setSeed(0x12345678L);
    for (int i = 1; i <= 62; i++) {
      final long inputValue = 1L << (i - 1);
      new Encoder(randomRange,
          null,  // hmacSha256
          null,  // md5
          userSecret,  // userSecret
          "MyEncoder",  // encoderId
          numBits,  // numBits,
          0.25,  // probabilityF
          0.3,  // probabilityP
          0.7,  // probabilityQ
          1,  // numCohorts
          2)  // numBloomHashes
          .encodeBits(inputValue);
    }
  }

  @Test
  public void testGetEncoderId()  {
    Encoder encoder = new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                                  "Foo",  // encoderId
                                  8,  // numBits,
                                  13.0 / 128.0,  // probabilityF
                                  0.25,  // probabilityP
                                  0.75,  // probabilityQ
                                  1,  // numCohorts
                                  2);  // numBloomHashes
    assertEquals("Foo", encoder.getEncoderId());
  }
}
