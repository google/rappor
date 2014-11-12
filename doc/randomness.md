Generating Random Bits for RAPPOR
=================================

To ensure privacy, an application using RAPPOR must generate random bits in an
unpredictable manner.  In other words, an adversary that can predict the
sequence of random bits used can determine the true values being reported.

Generating random numbers is highly platform-specific -- even
language-specific.  So, libraries implementing RAPPOR should be parameterized
by an interface to generate random bits.  (This can be thought of as
"dependency injection".)

<!-- TODO: details on the interfaces, once we have them in more than one
     language -->


For now, we have collected some useful links.

Linux
-----

* [Myths about /dev/urandom](http://www.2uo.de/myths-about-urandom/) -- Nice
  article explaining implementation aspects of `/dev/urandom` and `/dev/random`
  on Linux.  (Summary: just use `/dev/urandom`, with caveats explained)

* [LWN on getrandom](http://lwn.net/Articles/606141/)
  ([patch](http://lwn.net/Articles/605828/)) -- A very recent addition to the
  Linux kernel.  As of this writing (11/2014), it's safe to say that very few
  applications use it.  The relevant change, involving an issue mentioned in
  the first link, involves the situation at system boot, when there is little
  entropy available.


<!-- TODO: other platforms.  Chrome uses /dev/urandom on Linux.  What about
     other platforms?  -->

<!-- TODO: when we have a C/C++ client, explain provide sample implementation
     using simple C functions -->
