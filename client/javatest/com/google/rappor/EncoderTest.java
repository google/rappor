package com.google.rappor;

import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.lessThanOrEqualTo;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertThat;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.ExpectedException;
import org.junit.runner.RunWith;
import org.junit.runners.BlockJUnit4ClassRunner;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;

/**
 * Unit tests for {@link Encoder}.
 */
@RunWith(BlockJUnit4ClassRunner.class)
public class EncoderTest {
  @Rule
  public final ExpectedException thrown = ExpectedException.none();

  /**
   * Convert a human readable string to a 32 byte userSecret for testing.
   *
   * <p>Do not use this in a production environment!  For security, userSecret
   * must be at least 32 bytes of high-quality entropy.
   */
  private static byte[] makeTestingUserSecret(String testingSecret) throws Exception {
    // We generate the fake user secret by concatenating three copies of the
    // 16 byte MD5 hash of the testingSecret string encoded in UTF 8.
    MessageDigest md5 = MessageDigest.getInstance("MD5");
    byte[] digest = md5.digest(testingSecret.getBytes(StandardCharsets.UTF_8));
    assertEquals(16, digest.length);
    return ByteBuffer.allocate(48).put(digest).put(digest).put(digest).array();
  }

  private static long toLong(byte[] bytes) {
    assertThat(bytes.length, is(lessThanOrEqualTo(8)));
    ByteBuffer buffer = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).put(bytes);
    buffer.rewind(); // can't chain rewind() because it returns Buffer, not ByteBuffer.
    return buffer.getLong();
  }

  private static byte[] toBytes(long value) {
    return ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(value).array();
  }

  @Test
  public void testEncoderConstruction_goodArguments() throws Exception {
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
  public void testEncoderConstruction_userSecretTooShort() throws Exception {
    thrown.expect(IllegalArgumentException.class);
    byte[] tooShortSecret = new byte[47];
    new Encoder(tooShortSecret,  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                13.0 / 128.0,  // probabilityF
                0.25,  // probabilityP
                0.75,  // probabilityQ
                1,  // numCohorts
                2);  // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_userSecretMayBeLong() throws Exception {
    byte[] tooLongSecret = new byte[49];
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
  public void testEncoderConstruction_numBitsTooLow() throws Exception {
    thrown.expect(IllegalArgumentException.class);
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                0,  // numBits,
                13.0 / 128.0,  // probabilityF
                0.25,  // probabilityP
                0.75,  // probabilityQ
                1,  // numCohorts
                2);  // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_numBitsTooHigh() throws Exception {
    thrown.expect(IllegalArgumentException.class);
    new Encoder(
        makeTestingUserSecret("Bar"), // userSecret
        "Foo", // encoderId
        4097, // numBits,
        13.0 / 128.0, // probabilityF
        0.25, // probabilityP
        0.75, // probabilityQ
        1, // numCohorts
        2); // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_probabilityFTooLow() throws Exception {
    thrown.expect(IllegalArgumentException.class);
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                -0.01,  // probabilityF
                0.25,  // probabilityP
                0.75,  // probabilityQ
                1,  // numCohorts
                2);  // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_probabilityFTooHigh() throws Exception {
    thrown.expect(IllegalArgumentException.class);
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                1.01,  // probabilityF
                0.25,  // probabilityP
                0.75,  // probabilityQ
                1,  // numCohorts
                2);  // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_probabilityPTooLow() throws Exception {
    thrown.expect(IllegalArgumentException.class);
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                13.0 / 128.0,  // probabilityF
                -0.01,  // probabilityP
                0.75,  // probabilityQ
                1,  // numCohorts
                2);  // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_probabilityPTooHigh() throws Exception {
    thrown.expect(IllegalArgumentException.class);
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                13.0 / 128.0,  // probabilityF
                1.01,  // probabilityP
                0.75,  // probabilityQ
                1,  // numCohorts
                2);  // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_probabilityQTooLow() throws Exception {
    thrown.expect(IllegalArgumentException.class);
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                13.0 / 128.0,  // probabilityF
                0.25,  // probabilityP
                -0.01,  // probabilityQ
                1,  // numCohorts
                2);  // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_probabilityQTooHigh() throws Exception {
    thrown.expect(IllegalArgumentException.class);
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                13.0 / 128.0,  // probabilityF
                0.75,  // probabilityP
                1.01,  // probabilityQ
                1,  // numCohorts
                2);  // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_numCohortsTooLow() throws Exception {
    thrown.expect(IllegalArgumentException.class);
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                13.0 / 128.0,  // probabilityF
                0.25,  // probabilityP
                0.75,  // probabilityQ
                0,  // numCohorts
                2);  // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_numCohortsTooHigh() throws Exception {
    thrown.expect(IllegalArgumentException.class);
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                13.0 / 128.0,  // probabilityF
                0.25,  // probabilityP
                0.75,  // probabilityQ
                Encoder.MAX_COHORTS + 1,  // numCohorts
                2);  // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_numCohortsNotPowerOf2() throws Exception {
    thrown.expect(IllegalArgumentException.class);
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                13.0 / 128.0,  // probabilityF
                0.25,  // probabilityP
                0.75,  // probabilityQ
                3,  // numCohorts
                2);  // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_numBloomHashesTooLow() throws Exception {
    thrown.expect(IllegalArgumentException.class);
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                13.0 / 128.0,  // probabilityF
                0.25,  // probabilityP
                0.75,  // probabilityQ
                1,  // numCohorts
                0);  // numBloomHashes
  }

  @Test
  public void testEncoderConstruction_numBloomHashesTooHigh() throws Exception {
    thrown.expect(IllegalArgumentException.class);
    new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                13.0 / 128.0,  // probabilityF
                0.25,  // probabilityP
                0.75,  // probabilityQ
                1,  // numCohorts
                9);  // numBloomHashes
  }

  @Test
  public void testEncoderGetCohort() throws Exception {
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
            .getCohort());

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
            .getCohort());

    // Changing the user secret changes the cohort.
    assertEquals(
        3,
        new Encoder(
                makeTestingUserSecret("Bar"), // userSecret
                "Foo", // encoderId
                8, // numBits,
                13.0 / 128.0, // probabilityF
                0.25, // probabilityP
                0.75, // probabilityQ
                4, // numCohorts
                2) // numBloomHashes
            .getCohort());

    assertEquals(
        0,
        new Encoder(
                makeTestingUserSecret("Bar2"), // userSecret
                "Foo", // encoderId
                8, // numBits,
                13.0 / 128.0, // probabilityF
                0.25, // probabilityP
                0.75, // probabilityQ
                4, // numCohorts
                2) // numBloomHashes
            .getCohort());

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
            .getCohort());

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
            .getCohort());

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
            .getCohort());

    // Cohort assignments are bit-wise subsets
    int cohortAssignmentBig =
        new Encoder(
                makeTestingUserSecret("Bar"), // userSecret
                "Foo", // encoderId
                8, // numBits,
                13.0 / 128.0, // probabilityF
                0.25, // probabilityP
                0.75, // probabilityQ
                Encoder.MAX_COHORTS, // numCohorts
                2) // numBloomHashes
            .getCohort();

    int numCohortsSmall = Encoder.MAX_COHORTS / 2;
    // Verify that numCohortsSmall is a power of 2.
    assertEquals(0, numCohortsSmall & (numCohortsSmall - 1));
    int cohortAssignmentSmall =
        new Encoder(
                makeTestingUserSecret("Bar"), // userSecret
                "Foo", // encoderId
                8, // numBits,
                13.0 / 128.0, // probabilityF
                0.25, // probabilityP
                0.75, // probabilityQ
                numCohortsSmall, // numCohorts
                2) // numBloomHashes
            .getCohort();

    // This validates that the test case is well chosen.  If it fails, select a different userSecret
    // or encoderId.
    assertNotEquals(cohortAssignmentBig, cohortAssignmentSmall);

    // Test that cohortAssignmentSmall is a suffix of cohortAssignmentBig when represented in
    // binary.
    assertEquals(cohortAssignmentBig & (numCohortsSmall - 1), cohortAssignmentSmall);
  }

  @Test
  public void testEncoderEncodeBits_identity() throws Exception {
    assertEquals(
        0b11111101L,
        toLong(
            new Encoder(
                    makeTestingUserSecret("Bar"), // userSecret
                    "Foo", // encoderId
                    8, // numBits,
                    0, // probabilityF
                    0, // probabilityP
                    1, // probabilityQ
                    1, // numCohorts
                    2) // numBloomHashes
                .encodeBits(toBytes(0b11111101L))));

    assertEquals(
        0xD56B8119L,
        toLong(
            new Encoder(
                    makeTestingUserSecret("Bar"), // userSecret
                    "Foo", // encoderId
                    32, // numBits,
                    0, // probabilityF
                    0, // probabilityP
                    1, // probabilityQ
                    1, // numCohorts
                    2) // numBloomHashes
                .encodeBits(toBytes(0xD56B8119L))));
  }

  @Test
  public void testEncoderEncodeBits_tooHigh() throws Exception {
    Encoder encoder = new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                8,  // numBits,
                0,  // probabilityF
                0,  // probabilityP
                1,  // probabilityQ
                1,  // numCohorts
                2);  // numBloomHashes
    thrown.expect(IllegalArgumentException.class);
    encoder.encodeBits(toBytes(0x100)); // 9 bits
  }

  @Test
  public void testEncoderEncodeBoolean_identity() throws Exception {
    assertEquals(
        0x1L,
        toLong(
            new Encoder(
                    makeTestingUserSecret("Bar"), // userSecret
                    "Foo", // encoderId
                    1, // numBits,
                    0, // probabilityF
                    0, // probabilityP
                    1, // probabilityQ
                    1, // numCohorts
                    1) // numBloomHashes
                .encodeBoolean(true)));

    assertEquals(
        0x0L,
        toLong(
            new Encoder(
                    makeTestingUserSecret("Bar"), // userSecret
                    "Foo", // encoderId
                    1, // numBits,
                    0, // probabilityF
                    0, // probabilityP
                    1, // probabilityQ
                    1, // numCohorts
                    1) // numBloomHashes
                .encodeBoolean(false)));
  }

  @Test
  public void testEncoderEncodeOrdinal_identity() throws Exception {
    assertEquals(
        0b000000000001L,
        toLong(
            new Encoder(
                    makeTestingUserSecret("Bar"), // userSecret
                    "Foo", // encoderId
                    12, // numBits,
                    0, // probabilityF
                    0, // probabilityP
                    1, // probabilityQ
                    1, // numCohorts
                    1) // numBloomHashes
                .encodeOrdinal(0)));

    assertEquals(
        0b100000000000L,
        toLong(
            new Encoder(
                    makeTestingUserSecret("Bar"), // userSecret
                    "Foo", // encoderId
                    12, // numBits,
                    0, // probabilityF
                    0, // probabilityP
                    1, // probabilityQ
                    1, // numCohorts
                    1) // numBloomHashes
                .encodeOrdinal(11)));
  }

  @Test
  public void testEncoderEncodeOrdinal_tooLow() throws Exception {
    Encoder encoder = new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                12,  // numBits,
                0,  // probabilityF
                0,  // probabilityP
                1,  // probabilityQ
                1,  // numCohorts
                1);  // numBloomHashes
    thrown.expect(IllegalArgumentException.class);
    encoder.encodeOrdinal(-1);
  }

  @Test
  public void testEncoderEncodeOrdinal_tooHigh() throws Exception {
    Encoder encoder = new Encoder(makeTestingUserSecret("Bar"),  // userSecret
                "Foo",  // encoderId
                12,  // numBits,
                0,  // probabilityF
                0,  // probabilityP
                1,  // probabilityQ
                1,  // numCohorts
                1);  // numBloomHashes
    thrown.expect(IllegalArgumentException.class);
    encoder.encodeOrdinal(12);
  }

  @Test
  public void testEncoderEncodeString_identity() throws Exception {
    assertEquals(
        0b000010000100L,
        toLong(
            new Encoder(
                    makeTestingUserSecret("Bar"), // userSecret
                    "Foo", // encoderId
                    12, // numBits,
                    0, // probabilityF
                    0, // probabilityP
                    1, // probabilityQ
                    1, // numCohorts (so must be cohort 0)
                    2) // numBloomHashes
                .encodeString("Whizbang")));

    // Changing the user but keeping the cohort the same (both cohort 0)
    // results in the same encoding.
    assertEquals(
        0b000010000100L,
        toLong(
            new Encoder(
                    makeTestingUserSecret("Blotto"), // userSecret
                    "Foo", // encoderId
                    12, // numBits,
                    0, // probabilityF
                    0, // probabilityP
                    1, // probabilityQ
                    1, // numCohorts (so must be cohort 0)
                    2) // numBloomHashes
                .encodeString("Whizbang")));

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
    assertEquals(3, cohortProbeEncoder.getCohort());
    assertEquals(0b000011000000L, toLong(cohortProbeEncoder.encodeString("Whizbang")));

    // Changing the string gets a different encoding.
    assertEquals(
        0b001001000000L,
        toLong(
            new Encoder(
                    makeTestingUserSecret("Bar"), // userSecret
                    "Foo", // encoderId
                    12, // numBits,
                    0, // probabilityF
                    0, // probabilityP
                    1, // probabilityQ
                    1, // numCohorts (so must be cohort 0)
                    2) // numBloomHashes
                .encodeString("Xyzzy")));

    assertEquals(
        0b000000110000L,
        toLong(
            new Encoder(
                    makeTestingUserSecret("Bar"), // userSecret
                    "Foo", // encoderId
                    12, // numBits,
                    0, // probabilityF
                    0, // probabilityP
                    1, // probabilityQ
                    1, // numCohorts (so must be cohort 0)
                    2) // numBloomHashes
                .encodeString("Thud")));
  }


  @Test
  public void testEncoderEncodeBits_prrMemoizes() throws Exception {
    assertEquals(
        0b01110101L,
        toLong(
            new Encoder(
                    makeTestingUserSecret("Bar"), // userSecret
                    "Foo", // encoderId
                    8, // numBits,
                    0.25, // probabilityF
                    0, // probabilityP
                    1, // probabilityQ
                    1, // numCohorts
                    2) // numBloomHashes
                .encodeBits(toBytes(0b11111101L))));

    assertEquals(
        0b11111101L,
        toLong(
            new Encoder(
                    makeTestingUserSecret("Baz"), // userSecret
                    "Foo", // encoderId
                    8, // numBits,
                    0.25, // probabilityF
                    0, // probabilityP
                    1, // probabilityQ
                    1, // numCohorts
                    2) // numBloomHashes
                .encodeBits(toBytes(0b11111101L))));
  }

  @Test
  public void testEncoderEncodeBits_prrFlipProbability() throws Exception {
    int numSamples = 10000;
    int numBits = 8;
    double probabilityF = 1.0 / 32.0;
    long inputValue = 0b11111101L;

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
      long encoded = toLong(encoder.encodeBits(toBytes(inputValue)));
      assertEquals(encoded, toLong(encoder.encodeBits(toBytes(inputValue))));

      for (int iBit = 0; iBit < numBits; iBit++) {
        if ((encoded & (1L << iBit)) != 0) {
          counts[iBit]++;
        }
      }
    }

    assertEquals(9843, counts[0]); // input = 1, expectation = 9843.75
    assertEquals(173, counts[1]); // input = 0, expectation = 156.25
    assertEquals(9839, counts[2]); // input = 1, expectation = 9843.75
    assertEquals(9831, counts[3]); // input = 1, expectation = 9843.75
    assertEquals(9848, counts[4]); // input = 1, expectation = 9843.75
    assertEquals(9828, counts[5]); // input = 1, expectation = 9843.75
    assertEquals(9834, counts[6]); // input = 1, expectation = 9843.75
    assertEquals(9837, counts[7]); // input = 1, expectation = 9843.75

    // Check that no high-order bit past numBits ever got set.
    for (int iBit = numBits; iBit < 64; iBit++) {
      assertEquals(0, counts[iBit]);
    }
  }

  @Test
  public void testEncoderEncodeBits_irrFlipProbability() throws Exception {
    int numBits = 8;
    double probabilityP = 0.25;
    double probabilityQ = 0.85;
    long inputValue = 0b11111101L;

    SecureRandom random = SecureRandom.getInstance("SHA1PRNG");
    random.setSeed(0x12345678L);

    int counts[] = new int[64];
    for (int iSample = 0; iSample < 10000; iSample++) {
      Encoder encoder =
          new Encoder(
              random,
              null, // md5
              null, // sha256
              makeTestingUserSecret("User" + iSample), // userSecret
              "Foo", // encoderId
              numBits, // numBits,
              0, // probabilityF
              probabilityP, // probabilityP
              probabilityQ, // probabilityQ
              1, // numCohorts
              2); // numBloomHashes
      long encoded = toLong(encoder.encodeBits(toBytes(inputValue)));

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
  public void testEncoderEncodeBits_endToEnd() throws Exception {
    int numBits = 8;

    long inputValue = 0b11111101L;
    long prrValue = 0b01110101L;
    long prrAndIrrValue = 0b01110110L;

    // Verify that PRR is working as expected.
    assertEquals(
        prrValue,
        toLong(
            new Encoder(
                    null,
                    null, // md5
                    null, // sha256
                    makeTestingUserSecret("Bar"), // userSecret
                    "Foo", // encoderId
                    numBits, // numBits,
                    0.25, // probabilityF
                    0, // probabilityP
                    1, // probabilityQ
                    1, // numCohorts
                    2) // numBloomHashes
                .encodeBits(toBytes(inputValue))));

    // Verify that IRR is working as expected.
    SecureRandom random1 = SecureRandom.getInstance("SHA1PRNG");
    random1.setSeed(0x12345678L);
    assertEquals(
        prrAndIrrValue,
        toLong(
            new Encoder(
                    random1,
                    null, // md5
                    null, // sha256
                    makeTestingUserSecret("Bar"), // userSecret
                    "Foo", // encoderId
                    numBits, // numBits,
                    0, // probabilityF
                    0.3, // probabilityP
                    0.7, // probabilityQ
                    1, // numCohorts
                    2) // numBloomHashes
                .encodeBits(toBytes(prrValue))));

    // Test that end-to-end is the result of PRR + IRR.
    SecureRandom random2 = SecureRandom.getInstance("SHA1PRNG");
    random2.setSeed(0x12345678L);
    assertEquals(
        prrAndIrrValue,
        toLong(
            new Encoder(
                    random2,
                    null, // md5
                    null, // sha256
                    makeTestingUserSecret("Bar"), // userSecret
                    "Foo", // encoderId
                    numBits, // numBits,
                    0.25, // probabilityF
                    0.3, // probabilityP
                    0.7, // probabilityQ
                    1, // numCohorts
                    2) // numBloomHashes
                .encodeBits(toBytes(inputValue))));
  }

  @Test
  public void testEncoderEncodeBits_32BitValuesEncodeSuccessfully() throws Exception {
    // Regression test for b/22035650.
    int numBits = 32;
    byte[] userSecret = makeTestingUserSecret("Bar");

    // Explicitly spot-check the output for 2^0 and 2^31.
    long inputValue0 = 1L;
    long outputValue0 = 590349342L;
    SecureRandom random0 = SecureRandom.getInstance("SHA1PRNG");
    random0.setSeed(0x12345678L);
    assertEquals(
        outputValue0,
        toLong(
            new Encoder(
                    random0,
                    null, // md5
                    null, // sha256
                    userSecret, // userSecret
                    "MyEncoder", // encoderId
                    numBits, // numBits,
                    0.25, // probabilityF
                    0.3, // probabilityP
                    0.7, // probabilityQ
                    1, // numCohorts
                    2) // numBloomHashes
                .encodeBits(toBytes(inputValue0))));

    long inputValue31 = 1L << 31;
    long outputValue31 = 2746482838L;
    SecureRandom random31 = SecureRandom.getInstance("SHA1PRNG");
    random31.setSeed(0x12345678L);
    assertEquals(
        outputValue31,
        toLong(
            new Encoder(
                    random31,
                    null, // md5
                    null, // sha256
                    userSecret, // userSecret
                    "MyEncoder", // encoderId
                    numBits, // numBits,
                    0.25, // probabilityF
                    0.3, // probabilityP
                    0.7, // probabilityQ
                    1, // numCohorts
                    2) // numBloomHashes
                .encodeBits(toBytes(inputValue31))));

    // Check the range 2^1 to 2^30, making sure no values produce exceptions.
    SecureRandom randomRange = SecureRandom.getInstance("SHA1PRNG");
    randomRange.setSeed(0x12345678L);
    for (int i = 1; i <= 30; i++) {
      long inputValue = 1L << (i - 1);
      new Encoder(
              randomRange,
              null, // md5
              null, // sha256
              userSecret, // userSecret
              "MyEncoder", // encoderId
              numBits, // numBits,
              0.25, // probabilityF
              0.3, // probabilityP
              0.7, // probabilityQ
              1, // numCohorts
              2) // numBloomHashes
          .encodeBits(toBytes(inputValue));
    }
  }

  @Test
  public void testEncoderEncodeBits_63BitValuesEncodeSuccessfully() throws Exception {
    int numBits = 63;
    byte[] userSecret = makeTestingUserSecret("Bar");

    // Explicitly spot-check the output for 2^0 and 2^63.
    long inputValue0 = 1L;
    long outputValue0 = 867402030798341150L;
    SecureRandom random0 = SecureRandom.getInstance("SHA1PRNG");
    random0.setSeed(0x12345678L);
    assertEquals(
        outputValue0,
        toLong(
            new Encoder(
                    random0,
                    null, // md5
                    null, // sha256
                    userSecret, // userSecret
                    "MyEncoder", // encoderId
                    numBits, // numBits,
                    0.25, // probabilityF
                    0.3, // probabilityP
                    0.7, // probabilityQ
                    1, // numCohorts
                    2) // numBloomHashes
                .encodeBits(toBytes(inputValue0))));

    long inputValue63 = 1L << 62;
    long outputValue63 = 5497102447743615126L;
    SecureRandom random63 = SecureRandom.getInstance("SHA1PRNG");
    random63.setSeed(0x12345678L);
    assertEquals(
        outputValue63,
        toLong(
            new Encoder(
                    random63,
                    null, // md5
                    null, // sha256
                    userSecret, // userSecret
                    "MyEncoder", // encoderId
                    numBits, // numBits,
                    0.25, // probabilityF
                    0.3, // probabilityP
                    0.7, // probabilityQ
                    1, // numCohorts
                    2) // numBloomHashes
                .encodeBits(toBytes(inputValue63))));

    // Check the range 2^1 to 2^62, making sure no values produce exceptions.
    SecureRandom randomRange = SecureRandom.getInstance("SHA1PRNG");
    randomRange.setSeed(0x12345678L);
    for (int i = 1; i <= 62; i++) {
      long inputValue = 1L << (i - 1);
      new Encoder(
              randomRange,
              null, // md5
              null, // sha256
              userSecret, // userSecret
              "MyEncoder", // encoderId
              numBits, // numBits,
              0.25, // probabilityF
              0.3, // probabilityP
              0.7, // probabilityQ
              1, // numCohorts
              2) // numBloomHashes
          .encodeBits(toBytes(inputValue));
    }
  }

  @Test
  public void testEncoderEncodeBits_4096BitValuesEncodeSuccessfully() throws Exception {
    int numBits = 4096;
    byte[] userSecret = makeTestingUserSecret("Bar");

    // Check the range 2^1 to 2^4095, making sure no values produce exceptions.
    SecureRandom randomRange = SecureRandom.getInstance("SHA1PRNG");
    randomRange.setSeed(0x12345678L);
    // Stride is arbitrary, but chosen to be large enough to not cause too many probes (~40) and
    // prime to explore well.
    int stride = 97;
    for (int i = 1; i < numBits; i += stride) {
      new Encoder(
              randomRange,
              null, // md5
              null, // sha256
              userSecret, // userSecret
              "MyEncoder", // encoderId
              numBits, // numBits,
              0.25, // probabilityF
              0.3, // probabilityP
              0.7, // probabilityQ
              1, // numCohorts
              2) // numBloomHashes
          .encodeOrdinal(i);
    }
  }

  @Test
  public void testGetEncoderId() throws Exception {
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
