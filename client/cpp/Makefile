
# Use protobuf compiler.
_tmp/rappor.pb.h: ../proto/rappor.proto
	protoc --cpp_out _tmp --proto_path=../proto ../proto/rappor.proto

# NOTES:
# -lcrypto from openssl
# -g for debug info

# TODO: Instead of listing header files here, use gcc -M and Make features.
_tmp/rappor_sim: encoder.cc encoder.h rappor_deps.h \
	libc_rand_impl.cc libc_rand_impl.h \
	unix_kernel_rand_impl.cc unix_kernel_rand_impl.h \
	openssl_hash_impl.cc \
	rappor_sim.cc 
	$(CXX) \
    -Wall \
    -o _tmp/rappor_sim \
    encoder.cc \
		libc_rand_impl.cc unix_kernel_rand_impl.cc openssl_hash_impl.cc \
		rappor_sim.cc \
    -lcrypto \
		-g

_tmp/protobuf_encoder_test: encoder.cc encoder.h rappor_deps.h \
	libc_rand_impl.cc libc_rand_impl.h \
	unix_kernel_rand_impl.cc unix_kernel_rand_impl.h \
	openssl_hash_impl.cc \
	rappor_sim.cc \
 	_tmp/rappor.pb.h \
	protobuf_encoder.cc protobuf_encoder.h
	$(CXX) \
    -Wall \
    -o _tmp/protobuf_encoder_test \
		-I _tmp \
    encoder.cc \
		libc_rand_impl.cc unix_kernel_rand_impl.cc openssl_hash_impl.cc \
		_tmp/rappor.pb.cc \
		protobuf_encoder.cc \
		protobuf_encoder_test.cc \
    -lprotobuf \
    -lcrypto \
		-g

# c++0x for std::array
		#-std=c++0x 
_tmp/openssl_hash_impl_test: openssl_hash_impl_test.cc openssl_hash_impl.cc
	$(CXX) \
    -Wall \
    -o _tmp/openssl_hash_impl_test \
    openssl_hash_impl_test.cc openssl_hash_impl.cc \
	  -lcrypto
# OpenSSL provides libssl or libcrypto

clean:
	rm _tmp/* || true
