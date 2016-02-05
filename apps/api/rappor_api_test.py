#!/usr/bin/python -S
"""
rappor_api_test.py: Tests for rappor_api.py
"""

import unittest

import rappor_api  # module under test


class ApiTest(unittest.TestCase):
  # The tests are often in shell, but we can unit test stuff here too.

  def testHomeHandler(self):
    h = rappor_api.HomeHandler()
    response = h({})
    self.assertEqual('200 OK', response.Status())


if __name__ == '__main__':
  unittest.main()
