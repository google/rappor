# Build RAPPOR C++ code.

default : \
	_tmp/rappor_sim \
	_tmp/encoder_demo \
	_tmp/protobuf_encoder_demo \
	_tmp/openssl_hash_impl_test

# All intermediate files live in _tmp/
clean :
	rm -f --verbose _tmp/*

# Use protobuf compiler to generate .cc and .h files.  The .o and the .d depend
# on .cc, so that is the target of this rule.

_tmp/%.pb.cc : ../proto/%.proto
	protoc --cpp_out _tmp --proto_path=../proto $<

#
# Generate .d Makefile fragments.
#

# CXX flags:
#   -MM: exclude system headers
#   -I _tmp: So that protobuf files found
#
# Makefile stuff:
#   $*: the part that matched the wildcard, e.g. 'rappor_sim' for '%.cc'
#   matching 'rappor_sim.cc'
#
#   We use $< (first prereq) to generate .d and and .o files from .cc, because
#   it only needs the .cc file.  We used $^ (all prereqs) to pass ALL the .o
#   files to the link step.

_tmp/%.d : %.cc
	./dotd.sh $* $@ \
		$(CXX) -I _tmp/ -MM $(CPPFLAGS) $<

# Special case for .d file of generated source.
_tmp/%.pb.d : _tmp/%.pb.cc
	./dotd.sh $*.pb $@ \
		$(CXX) -I _tmp/ -MM $(CPPFLAGS) $<

#
# Include the Makefile fragments we generated, so that changes to headers will
# rebuild both .d files and .o files.  ('-include' suppresses the error if they
# don't exist.)
#
# NOTE: We have to list them explicitly.  Every time you add a source file, add
# the corresponding .d file here.
#

-include \
	_tmp/encoder.d \
	_tmp/libc_rand_impl.d \
	_tmp/openssl_hash_impl.d \
	_tmp/openssl_hash_impl_test.d \
	_tmp/protobuf_encoder.d \
	_tmp/protobuf_encoder_demo.d \
	_tmp/rappor_sim.d \
	_tmp/unix_kernel_rand_impl.d \
	_tmp/rappor.pb.d \
  _tmp/example_app.pb.d

# For example, -Wextra warns about unused params, but -Wall doesn't.
CXXFLAGS = -Wall -Wextra #-Wpedantic

#
# Build object files (-c: compile only)
#

# NOTE: More prerequisites to _tmp/%.o (header files) are added by the .d
# files, so we need $<.
_tmp/%.o : %.cc
	$(CXX) $(CXXFLAGS) -I _tmp/ -c -o $@ $<

_tmp/%.pb.o : _tmp/%.pb.cc
	$(CXX) $(CXXFLAGS) -I _tmp/ -c -o $@ $<

#
# Build executables
#

# CXX flag notes:
# -lcrypto from openssl
# -g for debug info
#
# You can add -std=c++0x for std::array, etc.

# $^ : all prerequisites
_tmp/rappor_sim : \
	_tmp/encoder.o \
	_tmp/libc_rand_impl.o \
	_tmp/unix_kernel_rand_impl.o \
	_tmp/openssl_hash_impl.o \
	_tmp/rappor_sim.o
	$(CXX) \
		$(CXXFLAGS) \
		-o $@ \
		$^ \
		-lcrypto \
		-g

# $^ : all prerequisites
_tmp/encoder_demo: \
	_tmp/encoder.o \
	_tmp/unix_kernel_rand_impl.o \
	_tmp/openssl_hash_impl.o \
	_tmp/encoder_demo.o
	$(CXX) \
		$(CXXFLAGS) \
		-o $@ \
		$^ \
		-lcrypto \
		-g

# -I _tmp for protobuf headers
_tmp/protobuf_encoder_demo : \
	_tmp/encoder.o \
	_tmp/libc_rand_impl.o \
	_tmp/unix_kernel_rand_impl.o \
	_tmp/openssl_hash_impl.o \
	_tmp/protobuf_encoder.o \
	_tmp/protobuf_encoder_demo.o \
	_tmp/example_app.pb.o \
	_tmp/rappor.pb.o
	$(CXX) \
		$(CXXFLAGS) \
		-I _tmp \
		-o $@ \
		$^ \
		-lprotobuf \
		-lcrypto \
		-g

_tmp/openssl_hash_impl_test : \
 	_tmp/openssl_hash_impl.o \
	_tmp/openssl_hash_impl_test.o
	$(CXX) \
		$(CXXFLAGS) \
		-o $@ \
		$^ \
		-lcrypto \
		-g

# Unittests are currently run manually, and require the Google gtest
# framework version 1.7.0 or greater, found at
#   https://github.com/google/googletest/releases
# TODO(mdeshon-google): Installer script
unittest: _tmp/openssl_hash_impl_unittest _tmp/encoder_unittest
	_tmp/openssl_hash_impl_unittest
	_tmp/encoder_unittest

_tmp/openssl_hash_impl_unittest: openssl_hash_impl_unittest.cc openssl_hash_impl.cc
	$(CXX) -g -o $@  $^ -lssl -lcrypto -lgtest

_tmp/encoder_unittest: encoder_unittest.cc encoder.cc unix_kernel_rand_impl.cc openssl_hash_impl.cc
	$(CXX) -g -o $@  $^ -lssl -lcrypto -lgtest
