# Build RAPPOR C++ code.

default: \
	_tmp/rappor_sim \
	_tmp/protobuf_encoder_demo \
	_tmp/openssl_hash_impl_test

clean:
	rm -f --verbose _tmp/*

# Use protobuf compiler to generate .cc and .h files.  The .o and the .d depend
# on .cc, so that is the target of this rule.

_tmp/rappor.pb.cc: ../proto/rappor.proto
	protoc --cpp_out _tmp --proto_path=../proto ../proto/rappor.proto

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
_tmp/rappor.pb.d : _tmp/rappor.pb.cc
	./dotd.sh rappor.pb $@ \
		$(CXX) -I _tmp/ -MM $(CPPFLAGS) $<

SOURCES = \
	encoder.cc \
	libc_rand_impl.cc \
	openssl_hash_impl.cc \
	openssl_hash_impl_test.cc \
	protobuf_encoder.cc \
	protobuf_encoder_demo.cc \
	rappor_sim.cc \
	unix_kernel_rand_impl.cc

# Don't need this now.  If there is more than one, we can generalize it.
# GENERATED_SOURCES = \
#	_tmp/rappor.pb.cc

#
# Include the Makefile fragments we generated, so that changes to headers will
# rebuild both .d files and .o files.  ('-include' suppresses the error if they
# don't exist.)
#

-include $(patsubst %.cc,_tmp/%.d,$(SOURCES))

-include _tmp/rappor.pb.d

# For example, -Wextra warns about unused params, but -Wall doesn't.
CXXFLAGS = -Wall -Wextra -Wpedantic

#
# Build object files (-c: compile only)
#

# NOTE: More prerequisites to _tmp/%.o (header files) are added by the .d
# files, so we need $<.
_tmp/%.o : %.cc
	$(CXX) $(CXXFLAGS) -I _tmp/ -c -o $@ $<

_tmp/rappor.pb.o : _tmp/rappor.pb.cc
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
_tmp/rappor_sim: \
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

# -I _tmp for protobuf headers
_tmp/protobuf_encoder_demo: \
	_tmp/encoder.o \
	_tmp/libc_rand_impl.o \
	_tmp/unix_kernel_rand_impl.o \
	_tmp/openssl_hash_impl.o \
	_tmp/protobuf_encoder.o \
	_tmp/protobuf_encoder_demo.o \
	_tmp/rappor.pb.o
	$(CXX) \
		$(CXXFLAGS) \
		-I _tmp \
		-o $@ \
		$^ \
		-lprotobuf \
		-lcrypto \
		-g

_tmp/openssl_hash_impl_test: \
 	_tmp/openssl_hash_impl.o \
	_tmp/openssl_hash_impl_test.o
	$(CXX) \
		$(CXXFLAGS) \
		-o $@ \
		$^ \
		-lcrypto \
		-g
