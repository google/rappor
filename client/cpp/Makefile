# Build RAPPOR C++ code.

default: \
	_tmp/rappor_sim \
	_tmp/protobuf_encoder_test \
	_tmp/openssl_hash_impl_test

clean:
	rm -f --verbose _tmp/*

# Use protobuf compiler to generate .cc and .h files.  The .o and the .d depend
# on .cc, so that is the target here.

_tmp/rappor.pb.cc: ../proto/rappor.proto
	protoc --cpp_out _tmp --proto_path=../proto ../proto/rappor.proto

# Generate .d Makefile fragments, so we can use #include statements in source
# for dependency info.  Adapted from the GNU make manual:
#
# http://www.gnu.org/software/make/manual/html_node/Automatic-Prerequisites.html#Automatic-PrerequisitesR
#
# $*: the part that matched the wildcard, e.g. 'rappor_sim' for '%.cc' matching
# 'rappor_sim.cc'

# -MM: exclude system headers
# $$$$: PID escaped
# -I _tmp: So that protobuf files found
#
# TODO: The whole thing could be in bash.
# 
# We use $< (first prereq) to generate .d and and .o files from .cc, because it
# only needs the .cc file.
# $^ (all prereqs) is used to pass all the .o files to the link step.

_tmp/%.d : %.cc
	basename=$* && \
	./dotd.sh $$basename $@ \
		$(CXX) -I _tmp/ -MM $(CPPFLAGS) $<

# Special case for .d file of generated source.
_tmp/rappor.pb.d : _tmp/rappor.pb.cc
	basename=rappor.pb && \
	./dotd.sh $$basename $@ \
		$(CXX) -I _tmp/ -MM $(CPPFLAGS) $<

SOURCES = \
	encoder.cc \
	libc_rand_impl.cc \
	openssl_hash_impl.cc \
	openssl_hash_impl_test.cc \
	protobuf_encoder.cc \
	protobuf_encoder_test.cc \
	rappor_sim.cc \
	unix_kernel_rand_impl.cc

# Don't need this now.  If there is more than one, we can generalize it.
# GENERATED_SOURCES = \
#	_tmp/rappor.pb.cc

# include all the Makefile fragments.
# -include doesn't display a message if they don't exist.

-include $(patsubst %.cc,_tmp/%.d,$(SOURCES))

-include _tmp/rappor.pb.d

CXXFLAGS = -Wall

# -c: compile only

_tmp/%.o : %.cc
	$(CXX) $(CXXFLAGS) -I _tmp/ -c -o $@ $<

_tmp/rappor.pb.o : _tmp/rappor.pb.cc
	$(CXX) $(CXXFLAGS) -I _tmp/ -c -o $@ $<

# NOTES:
# -lcrypto from openssl
# -g for debug info

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
_tmp/protobuf_encoder_test: \
	_tmp/encoder.o \
	_tmp/libc_rand_impl.o \
	_tmp/unix_kernel_rand_impl.o \
	_tmp/openssl_hash_impl.o \
	_tmp/protobuf_encoder.o \
	_tmp/protobuf_encoder_test.o \
	_tmp/rappor.pb.o
	$(CXX) \
		$(CXXFLAGS) \
		-I _tmp \
		-o $@ \
		$^ \
		-lprotobuf \
		-lcrypto \
		-g

# for std::array:
# -std=c++0x

_tmp/openssl_hash_impl_test: \
 	_tmp/openssl_hash_impl.o \
	_tmp/openssl_hash_impl_test.o
	$(CXX) \
		$(CXXFLAGS) \
		-o $@ \
		$^ \
		-lcrypto \
		-g
