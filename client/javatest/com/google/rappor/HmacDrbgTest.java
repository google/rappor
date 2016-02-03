package com.google.rappor;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;

import com.google.common.io.BaseEncoding;
import com.google.common.primitives.Bytes;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.junit.runners.JUnit4;

/**
 * Unit tests for {@link HmacDrbg}.
 *
 * Test vectors come from NIST's SHA-256 HMAC_DRBG no reseed known input test vectors at
 * http://csrc.nist.gov/groups/STM/cavp/random-number-generation.html#drbgvs
 */
@RunWith(JUnit4.class)
public final class HmacDrbgTest {

  private byte[] hexToBytes(String s) {
    return BaseEncoding.base16().decode(s.toUpperCase());
  }

  // ==== Test vectors for HMAC_DRBG with no personalization. ====
  @Test
  public void testHmacDrbgNistCase0() {
    byte[] entropy =
      hexToBytes("ca851911349384bffe89de1cbdc46e6831e44d34a4fb935ee285dd14b71a7488");
    byte[] nonce = hexToBytes("659ba96c601dc69fc902940805ec0ca8");
    byte[] expected = hexToBytes(
      "e528e9abf2dece54d47c7e75e5fe302149f817ea9fb4bee6f4199697d04d5b89"
      + "d54fbb978a15b5c443c9ec21036d2460b6f73ebad0dc2aba6e624abf07745bc1"
      + "07694bb7547bb0995f70de25d6b29e2d3011bb19d27676c07162c8b5ccde0668"
      + "961df86803482cb37ed6d5c0bb8d50cf1f50d476aa0458bdaba806f48be9dcb8");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistCase1() {
    byte[] entropy =
      hexToBytes("79737479ba4e7642a221fcfd1b820b134e9e3540a35bb48ffae29c20f5418ea3");
    byte[] nonce = hexToBytes("3593259c092bef4129bc2c6c9e19f343");
    byte[] expected = hexToBytes(
      "cf5ad5984f9e43917aa9087380dac46e410ddc8a7731859c84e9d0f31bd43655"
      + "b924159413e2293b17610f211e09f770f172b8fb693a35b85d3b9e5e63b1dc25"
      + "2ac0e115002e9bedfb4b5b6fd43f33b8e0eafb2d072e1a6fee1f159df9b51e6c"
      + "8da737e60d5032dd30544ec51558c6f080bdbdab1de8a939e961e06b5f1aca37");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistCase2() {
    byte[] entropy =
      hexToBytes("b340907445b97a8b589264de4a17c0bea11bb53ad72f9f33297f05d2879d898d");
    byte[] nonce = hexToBytes("65cb27735d83c0708f72684ea58f7ee5");
    byte[] expected = hexToBytes(
      "75183aaaf3574bc68003352ad655d0e9ce9dd17552723b47fab0e84ef903694a"
      + "32987eeddbdc48efd24195dbdac8a46ba2d972f5808f23a869e71343140361f5"
      + "8b243e62722088fe10a98e43372d252b144e00c89c215a76a121734bdc485486"
      + "f65c0b16b8963524a3a70e6f38f169c12f6cbdd169dd48fe4421a235847a23ff");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistCase3() {
    byte[] entropy =
      hexToBytes("8e159f60060a7d6a7e6fe7c9f769c30b98acb1240b25e7ee33f1da834c0858e7");
    byte[] nonce = hexToBytes("c39d35052201bdcce4e127a04f04d644");
    byte[] expected = hexToBytes(
      "62910a77213967ea93d6457e255af51fc79d49629af2fccd81840cdfbb491099"
      + "1f50a477cbd29edd8a47c4fec9d141f50dfde7c4d8fcab473eff3cc2ee9e7cc9"
      + "0871f180777a97841597b0dd7e779eff9784b9cc33689fd7d48c0dcd341515ac"
      + "8fecf5c55a6327aea8d58f97220b7462373e84e3b7417a57e80ce946d6120db5");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistCase4() {
    byte[] entropy =
      hexToBytes("74755f196305f7fb6689b2fe6835dc1d81484fc481a6b8087f649a1952f4df6a");
    byte[] nonce = hexToBytes("c36387a544a5f2b78007651a7b74b749");
    byte[] expected = hexToBytes(
      "b2896f3af4375dab67e8062d82c1a005ef4ed119d13a9f18371b1b8737744186"
      + "84805fd659bfd69964f83a5cfe08667ddad672cafd16befffa9faed49865214f"
      + "703951b443e6dca22edb636f3308380144b9333de4bcb0735710e4d926678634"
      + "2fc53babe7bdbe3c01a3addb7f23c63ce2834729fabbd419b47beceb4a460236");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistCase5() {
    byte[] entropy =
      hexToBytes("4b222718f56a3260b3c2625a4cf80950b7d6c1250f170bd5c28b118abdf23b2f");
    byte[] nonce = hexToBytes("7aed52d0016fcaef0b6492bc40bbe0e9");
    byte[] expected = hexToBytes(
      "a6da029b3665cd39fd50a54c553f99fed3626f4902ffe322dc51f0670dfe8742"
      + "ed48415cf04bbad5ed3b23b18b7892d170a7dcf3ef8052d5717cb0c1a8b3010d"
      + "9a9ea5de70ae5356249c0e098946030c46d9d3d209864539444374d8fbcae068"
      + "e1d6548fa59e6562e6b2d1acbda8da0318c23752ebc9be0c1c1c5b3cf66dd967");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistCase6() {
    byte[] entropy =
      hexToBytes("b512633f27fb182a076917e39888ba3ff35d23c3742eb8f3c635a044163768e0");
    byte[] nonce = hexToBytes("e2c39b84629a3de5c301db5643af1c21");
    byte[] expected = hexToBytes(
      "fb931d0d0194a97b48d5d4c231fdad5c61aedf1c3a55ac24983ecbf38487b1c9"
      + "3396c6b86ff3920cfa8c77e0146de835ea5809676e702dee6a78100da9aa43d8"
      + "ec0bf5720befa71f82193205ac2ea403e8d7e0e6270b366dc4200be26afd9f63"
      + "b7e79286a35c688c57cbff55ac747d4c28bb80a2b2097b3b62ea439950d75dff");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistCase7() {
    byte[] entropy =
      hexToBytes("aae3ffc8605a975befefcea0a7a286642bc3b95fb37bd0eb0585a4cabf8b3d1e");
    byte[] nonce = hexToBytes("9504c3c0c4310c1c0746a036c91d9034");
    byte[] expected = hexToBytes(
      "2819bd3b0d216dad59ddd6c354c4518153a2b04374b07c49e64a8e4d055575df"
      + "bc9a8fcde68bd257ff1ba5c6000564b46d6dd7ecd9c5d684fd757df62d852115"
      + "75d3562d7814008ab5c8bc00e7b5a649eae2318665b55d762de36eba00c2906c"
      + "0e0ec8706edb493e51ca5eb4b9f015dc932f262f52a86b11c41e9a6d5b3bd431");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistCase8() {
    byte[] entropy =
      hexToBytes("b9475210b79b87180e746df704b3cbc7bf8424750e416a7fbb5ce3ef25a82cc6");
    byte[] nonce = hexToBytes("24baf03599c10df6ef44065d715a93f7");
    byte[] expected = hexToBytes(
      "ae12d784f796183c50db5a1a283aa35ed9a2b685dacea97c596ff8c294906d1b"
      + "1305ba1f80254eb062b874a8dfffa3378c809ab2869aa51a4e6a489692284a25"
      + "038908a347342175c38401193b8afc498077e10522bec5c70882b7f760ea5946"
      + "870bd9fc72961eedbe8bff4fd58c7cc1589bb4f369ed0d3bf26c5bbc62e0b2b2");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistCase9() {
    byte[] entropy =
      hexToBytes("27838eb44ceccb4e36210703ebf38f659bc39dd3277cd76b7a9bcd6bc964b628");
    byte[] nonce = hexToBytes("39cfe0210db2e7b0eb52a387476e7ea1");
    byte[] expected = hexToBytes(
      "e5e72a53605d2aaa67832f97536445ab774dd9bff7f13a0d11fd27bf6593bfb5"
      + "2309f2d4f09d147192199ea584503181de87002f4ee085c7dc18bf32ce531564"
      + "7a3708e6f404d6588c92b2dda599c131aa350d18c747b33dc8eda15cf40e9526"
      + "3d1231e1b4b68f8d829f86054d49cfdb1b8d96ab0465110569c8583a424a099a");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistCase10() {
    byte[] entropy =
      hexToBytes("d7129e4f47008ad60c9b5d081ff4ca8eb821a6e4deb91608bf4e2647835373a5");
    byte[] nonce = hexToBytes("a72882773f78c2fc4878295840a53012");
    byte[] expected = hexToBytes(
      "0cbf48585c5de9183b7ff76557f8fc9ebcfdfde07e588a8641156f61b7952725"
      + "bbee954f87e9b937513b16bba0f2e523d095114658e00f0f3772175acfcb3240"
      + "a01de631c19c5a834c94cc58d04a6837f0d2782fa53d2f9f65178ee9c8372224"
      + "94c799e64c60406069bd319549b889fa00a0032dd7ba5b1cc9edbf58de82bfcd");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistCase11() {
    byte[] entropy =
      hexToBytes("67fe5e300c513371976c80de4b20d4473889c9f1214bce718bc32d1da3ab7532");
    byte[] nonce = hexToBytes("e256d88497738a33923aa003a8d7845c");
    byte[] expected = hexToBytes(
      "b44660d64ef7bcebc7a1ab71f8407a02285c7592d755ae6766059e894f694373"
      + "ed9c776c0cfc8594413eefb400ed427e158d687e28da3ecc205e0f7370fb0896"
      + "76bbb0fa591ec8d916c3d5f18a3eb4a417120705f3e2198154cd60648dbfcfc9"
      + "01242e15711cacd501b2c2826abe870ba32da785ed6f1fdc68f203d1ab43a64f");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistCase12() {
    byte[] entropy =
      hexToBytes("de8142541255c46d66efc6173b0fe3ffaf5936c897a3ce2e9d5835616aafa2cb");
    byte[] nonce = hexToBytes("d01f9002c407127bc3297a561d89b81d");
    byte[] expected = hexToBytes(
      "64d1020929d74716446d8a4e17205d0756b5264867811aa24d0d0da8644db25d"
      + "5cde474143c57d12482f6bf0f31d10af9d1da4eb6d701bdd605a8db74fb4e77f"
      + "79aaa9e450afda50b18d19fae68f03db1d7b5f1738d2fdce9ad3ee9461b58ee2"
      + "42daf7a1d72c45c9213eca34e14810a9fca5208d5c56d8066bab1586f1513de7");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistCase13() {
    byte[] entropy =
      hexToBytes("4a8e0bd90bdb12f7748ad5f147b115d7385bb1b06aee7d8b76136a25d779bcb7");
    byte[] nonce = hexToBytes("7f3cce4af8c8ce3c45bdf23c6b181a00");
    byte[] expected = hexToBytes(
      "320c7ca4bbeb7af977bc054f604b5086a3f237aa5501658112f3e7a33d2231f5"
      + "536d2c85c1dad9d9b0bf7f619c81be4854661626839c8c10ae7fdc0c0b571be3"
      + "4b58d66da553676167b00e7d8e49f416aacb2926c6eb2c66ec98bffae20864cf"
      + "92496db15e3b09e530b7b9648be8d3916b3c20a3a779bec7d66da63396849aaf");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistCase14() {
    byte[] entropy =
      hexToBytes("451ed024bc4b95f1025b14ec3616f5e42e80824541dc795a2f07500f92adc665");
    byte[] nonce = hexToBytes("2f28e6ee8de5879db1eccd58c994e5f0");
    byte[] expected = hexToBytes(
      "3fb637085ab75f4e95655faae95885166a5fbb423bb03dbf0543be063bcd4879"
      + "9c4f05d4e522634d9275fe02e1edd920e26d9accd43709cb0d8f6e50aa54a5f3"
      + "bdd618be23cf73ef736ed0ef7524b0d14d5bef8c8aec1cf1ed3e1c38a808b35e"
      + "61a44078127c7cb3a8fd7addfa50fcf3ff3bc6d6bc355d5436fe9b71eb44f7fd");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  // ==== Test vectors for HMAC_DRBG with personalization. ====
  @Test
  public void testHmacDrbgNistWithPersonalizationCase0() {
    byte[] entropy =
      hexToBytes("5cacc68165a2e2ee20812f35ec73a79dbf30fd475476ac0c44fc6174cdac2b55");
    byte[] nonce = hexToBytes("6f885496c1e63af620becd9e71ecb824");
    byte[] personalizationString =
      hexToBytes("e72dd8590d4ed5295515c35ed6199e9d211b8f069b3058caa6670b96ef1208d0");
    byte[] expected = hexToBytes(
      "f1012cf543f94533df27fedfbf58e5b79a3dc517a9c402bdbfc9a0c0f721f9d5"
      + "3faf4aafdc4b8f7a1b580fcaa52338d4bd95f58966a243cdcd3f446ed4bc546d"
      + "9f607b190dd69954450d16cd0e2d6437067d8b44d19a6af7a7cfa8794e5fbd72"
      + "8e8fb2f2e8db5dd4ff1aa275f35886098e80ff844886060da8b1e7137846b23b");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistWithPersonalizationCase1() {
    byte[] entropy =
      hexToBytes("8df013b4d103523073917ddf6a869793059e9943fc8654549e7ab22f7c29f122");
    byte[] nonce = hexToBytes("da2625af2ddd4abcce3cf4fa4659d84e");
    byte[] personalizationString =
      hexToBytes("b571e66d7c338bc07b76ad3757bb2f9452bf7e07437ae8581ce7bc7c3ac651a9");
    byte[] expected = hexToBytes(
      "b91cba4cc84fa25df8610b81b641402768a2097234932e37d590b1154cbd23f9"
      + "7452e310e291c45146147f0da2d81761fe90fba64f94419c0f662b28c1ed94da"
      + "487bb7e73eec798fbcf981b791d1be4f177a8907aa3c401643a5b62b87b89d66"
      + "b3a60e40d4a8e4e9d82af6d2700e6f535cdb51f75c321729103741030ccc3a56");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistWithPersonalizationCase2() {
    byte[] entropy =
      hexToBytes("565b2b77937ba46536b0f693b3d5e4a8a24563f9ef1f676e8b5b2ef17823832f");
    byte[] nonce = hexToBytes("4ef3064ec29f5b7f9686d75a23d170e3");
    byte[] personalizationString =
      hexToBytes("3b722433226c9dba745087270ab3af2c909425ba6d39f5ce46f07256068319d9");
    byte[] expected = hexToBytes(
      "d144ee7f8363d128872f82c15663fe658413cd42651098e0a7c51a970de75287"
      + "ec943f9061e902280a5a9e183a7817a44222d198fbfab184881431b4adf35d3d"
      + "1019da5a90b3696b2349c8fba15a56d0f9d010a88e3f9eeedb67a69bcaa71281"
      + "b41afa11af576b765e66858f0eb2e4ec4081609ec81da81df0a0eb06787340ea");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistWithPersonalizationCase3() {
    byte[] entropy =
      hexToBytes("fc3832a91b1dcdcaa944f2d93cbceb85c267c491b7b59d017cde4add79a836b6");
    byte[] nonce = hexToBytes("d5e76ce9eabafed06e33a913e395c5e0");
    byte[] personalizationString =
      hexToBytes("ffc5f6eefd51da64a0f67b5f0cf60d7ab43fc7836bca650022a0cee57a43c148");
    byte[] expected = hexToBytes(
      "0e713c6cc9a4dbd4249201d12b7bf5c69c3e18eb504bf3252db2f43675e17d99"
      + "b6a908400cea304011c2e54166dae1f20260008efe4e06a87e0ce525ca482bca"
      + "223a902a14adcf2374a739a5dfeaf14cadd72efa4d55d15154c974d9521535bc"
      + "b70658c5b6c944020afb04a87b223b4b8e5d89821704a9985bb010405ba8f3d4");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistWithPersonalizationCase4() {
    byte[] entropy =
      hexToBytes("8009eb2cb49fdf16403bcdfd4a9f952191062acb9cc111eca019f957fb9f4451");
    byte[] nonce = hexToBytes("355598866952394b1eddd85d59f81c9d");
    byte[] personalizationString =
      hexToBytes("09ff1d4b97d83b223d002e05f754be480d13ba968e5aac306d71cc9fc49cc2dd");
    byte[] expected = hexToBytes(
      "9550903c2f02cf77c8f9c9a37041d0040ee1e3ef65ba1a1fbbcf44fb7a2172bd"
      + "6b3aaabe850281c3a1778277bacd09614dfefececac64338ae24a1bf150cbf9d"
      + "9541173a82ecba08aa19b75abb779eb10efa4257d5252e8afcac414bc3bb5d30"
      + "06b6f36fb9daea4c8c359ef6cdbeff27c1068571dd3c89dc87eda9190086888d");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistWithPersonalizationCase5() {
    byte[] entropy =
      hexToBytes("a6e4c9a8bd6da23b9c2b10a7748fd08c4f782fadbac7ea501c17efdc6f6087bd");
    byte[] nonce = hexToBytes("acdc47edf1d3b21d0aec7631abb6d7d5");
    byte[] personalizationString =
      hexToBytes("c16ee0908a5886dccf332fbc61de9ec7b7972d2c4c83c477409ce8a15c623294");
    byte[] expected = hexToBytes(
      "a52f93ccb363e2bdf0903622c3caedb7cffd04b726052b8d455744c71b76dee1"
      + "b71db9880dc3c21850489cb29e412d7d80849cfa9151a151dcbf32a32b4a54ca"
      + "c01d3200200ed66a3a5e5c131a49655ffbf1a8824ff7f265690dffb4054df46a"
      + "707b9213924c631c5bce379944c856c4f7846e281ac89c64fad3a49909dfb92b");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistWithPersonalizationCase6() {
    byte[] entropy =
      hexToBytes("59d6307460a9bdd392dfc0904973991d585696010a71e52d590a5039b4849fa4");
    byte[] nonce = hexToBytes("34a0aafb95917cbf8c38fc5548373c05");
    byte[] personalizationString =
      hexToBytes("0407b7c57bc11361747c3d67526c36e228028a5d0b145d66ab9a2fe4b07507a0");
    byte[] expected = hexToBytes(
      "299aba0661315211b09d2861855d0b4b125ab24649461341af6abd903ed6f025"
      + "223b3299f2126fcad44c675166d800619cf49540946b12138989417904324b0d"
      + "dad121327211a297f11259c9c34ce4c70c322a653675f78d385e4e2443f8058d"
      + "141195e17e0bd1b9d44bf3e48c376e6eb44ef020b11cf03eb141c46ecb43cf3d");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistWithPersonalizationCase7() {
    byte[] entropy =
      hexToBytes("9ae3506aadbc8358696ba1ba17e876e1157b7048235921503d36d9211b430342");
    byte[] nonce = hexToBytes("9abf7d66afee5d2b811cba358bbc527d");
    byte[] personalizationString =
      hexToBytes("0d645f6238e9ceb038e4af9772426ca110c5be052f8673b8b5a65c4e53d2f519");
    byte[] expected = hexToBytes(
      "5f032c7fec6320fe423b6f38085cbad59d826085afe915247b3d546c4c6b1745"
      + "54dd4877c0d671de9554b505393a44e71f209b70f991ac8aa6e08f983fff2a4c"
      + "817b0cd26c12b2c929378506489a75b2025b358cb5d0400821e7e252ac6376cd"
      + "94a40c911a7ed8b6087e3de5fa39fa6b314c3ba1c593b864ce4ff281a97c325b");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistWithPersonalizationCase8() {
    byte[] entropy =
      hexToBytes("96ae3b8775b36da2a29b889ad878941f43c7d51295d47440cd0e3c4999193109");
    byte[] nonce = hexToBytes("1fe022a6fc0237b055d4d6a7036b18d5");
    byte[] personalizationString =
      hexToBytes("1e40e97362d0a823d3964c26b81ab53825c56446c5261689011886f19b08e5c2");
    byte[] expected = hexToBytes(
      "e707cd14b06ce1e6dbcceaedbf08d88891b03f44ad6a797bd12fdeb557d0151d"
      + "f9346a028dec004844ca46adec3051dafb345895fa9f4604d8a13c8ff66ae093"
      + "fa63c4d9c0816d55a0066d31e8404c841e87b6b2c7b5ae9d7afb6840c2f7b441"
      + "bf2d3d8bd3f40349c1c014347c1979213c76103e0bece26ad7720601eff42275");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistWithPersonalizationCase9() {
    byte[] entropy =
      hexToBytes("33f5120396336e51ee3b0b619b5f873db05ca57cda86aeae2964f51480d14992");
    byte[] nonce = hexToBytes("6f1f6e9807ba5393edcf3cb4e4bb6113");
    byte[] personalizationString =
      hexToBytes("3709605af44d90196867c927512aa8ba31837063337b4879408d91a05c8efa9f");
    byte[] expected = hexToBytes(
      "8b8291126ded9acef12516025c99ccce225d844308b584b872c903c7bc646759"
      + "9a1cead003dc4c70f6d519f5b51ce0da57f53da90dbe8f666a1a1dde297727fe"
      + "e2d44cebd1301fc1ca75956a3fcae0d374e0df6009b668fd21638d2b733e6902"
      + "d22d5bfb4af1b455975e08eef0ebe4dc87705801e7776583c8de11672729f723");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistWithPersonalizationCase10() {
    byte[] entropy =
      hexToBytes("ad300b799005f290fee7f930eebce158b98fb6cb449987fe433f955456b35300");
    byte[] nonce = hexToBytes("06aa2514e4bd114edf7ac105cfef2772");
    byte[] personalizationString =
      hexToBytes("87ada711465e4169da2a74c931afb9b5a5b190d07b7af342aa99570401c3ee8a");
    byte[] expected = hexToBytes(
      "80d7c606ff49415a3a92ba1f2943235c01339c8f9cd0b0511fbfdf3ef23c42ff"
      + "ff008524193faaa4b7f2f2eb0cfa221d9df89bd373fe4e158ec06fad3ecf1eb4"
      + "8b8239b0bb826ee69d773883a3e8edac66254610ff70b6609836860e39ea1f3b"
      + "fa04596fee1f2baca6cebb244774c6c3eb4af1f02899eba8f4188f91776de16f");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistWithPersonalizationCase11() {
    byte[] entropy =
      hexToBytes("130b044e2c15ab89375e54b72e7baae6d4cad734b013a090f4df057e634f6ff0");
    byte[] nonce = hexToBytes("65fd6ac602cd44107d705dbc066e52b6");
    byte[] personalizationString =
      hexToBytes("f374aba16f34d54aae5e494505b67d3818ef1c08ea24967a76876d4361379aec");
    byte[] expected = hexToBytes(
      "5d179534fb0dba3526993ed8e27ec9f915183d967336bb24352c67f4ab5d7935"
      + "d3168e57008da851515efbaecb69904b6d899d3bfa6e9805659aef2942c49038"
      + "75b8fcbc0d1d24d1c075f0ff667c1fc240d8b410dff582fa71fa30878955ce2e"
      + "d786ef32ef852706e62439b69921f26e84e0f54f62b938f04905f05fcd7c2204");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistWithPersonalizationCase12() {
    byte[] entropy =
      hexToBytes("716430e999964b35459c17921fe5f60e09bd9ab234cb8f4ba4932bec4a60a1d5");
    byte[] nonce = hexToBytes("9533b711e061b07d505da707cafbca03");
    byte[] personalizationString =
      hexToBytes("372ae616d1a1fc45c5aecad0939c49b9e01c93bfb40c835eebd837af747f079d");
    byte[] expected = hexToBytes(
      "a80d6a1b2d0ce01fe0d26e70fb73da20d45841cf01bfbd50b90d2751a46114c0"
      + "e758cb787d281a0a9cf62f5c8ce2ee7ca74fefff330efe74926acca6d6f0646e"
      + "4e3c1a1e52fce1d57b88beda4a5815896f25f38a652cc240deb582921c8b1d03"
      + "a1da966dd04c2e7eee274df2cd1837096b9f7a0d89a82434076bc30173229a60");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistWithPersonalizationCase13() {
    byte[] entropy =
      hexToBytes("7679f154296e6d580854826539003a82d1c54e2e062c619d00da6c6ac820789b");
    byte[] nonce = hexToBytes("55d12941b0896462e7d888e5322a99a3");
    byte[] personalizationString =
      hexToBytes("ba4d1ed696f58ef64596c76cee87cc1ca83069a79e7982b9a06f9d62f4209faf");
    byte[] expected = hexToBytes(
      "10dc7cd2bb68c2c28f76d1b04ae2aa287071e04c3b688e1986b05cc1209f691d"
      + "aa55868ebb05b633c75a40a32b49663185fe5bb8f906008347ef51590530948b"
      + "87613920014802e5864e0758f012e1eae31f0c4c031ef823aecfb2f8a73aaa94"
      + "6fc507037f9050b277bdeaa023123f9d22da1606e82cb7e56de34bf009eccb46");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgNistWithPersonalizationCase14() {
    byte[] entropy =
      hexToBytes("8ca4a964e1ff68753db86753d09222e09b888b500be46f2a3830afa9172a1d6d");
    byte[] nonce = hexToBytes("a59394e0af764e2f21cf751f623ffa6c");
    byte[] personalizationString =
      hexToBytes("eb8164b3bf6c1750a8de8528af16cffdf400856d82260acd5958894a98afeed5");
    byte[] expected = hexToBytes(
      "fc5701b508f0264f4fdb88414768e1afb0a5b445400dcfdeddd0eba67b4fea8c"
      + "056d79a69fd050759fb3d626b29adb8438326fd583f1ba0475ce7707bd294ab0"
      + "1743d077605866425b1cbd0f6c7bba972b30fbe9fce0a719b044fcc139435489"
      + "5a9f8304a2b5101909808ddfdf66df6237142b6566588e4e1e8949b90c27fc1f");

    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), personalizationString);
    byte[] out1 = new byte[1024 / 8];
    drbg.nextBytes(out1);
    byte[] out2 = new byte[1024 / 8];
    drbg.nextBytes(out2);
    assertArrayEquals(expected, out2);
  }

  @Test
  public void testHmacDrbgGenerateEntropyInput() {
    byte[] got = HmacDrbg.generateEntropyInput();
    assertEquals(got.length, HmacDrbg.ENTROPY_INPUT_SIZE_BYTES);
  }

  @Test
  public void testHmacDrbgZeroLengthOutput() {
    byte[] entropy =
      hexToBytes("8ca4a964e1ff68753db86753d09222e09b888b500be46f2a3830afa9172a1d6d");
    byte[] nonce = hexToBytes("a59394e0af764e2f21cf751f623ffa6c");
    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out = drbg.nextBytes(0);
    assertArrayEquals(new byte[0], out);
  }

  @Test
  public void testHmacDrbgCanGenerateMaxBytesOutput() {
    byte[] entropy =
      hexToBytes("8ca4a964e1ff68753db86753d09222e09b888b500be46f2a3830afa9172a1d6d");
    byte[] nonce = hexToBytes("a59394e0af764e2f21cf751f623ffa6c");
    HmacDrbg drbg = new HmacDrbg(Bytes.concat(entropy, nonce), null);
    byte[] out = drbg.nextBytes(HmacDrbg.MAX_BYTES_TOTAL);
    assertEquals(HmacDrbg.MAX_BYTES_TOTAL, out.length);
  }
}
