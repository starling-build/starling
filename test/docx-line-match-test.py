#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""Edge matching must tolerate bidi extraction order, not missing Arabic."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("line_match", Path(__file__).with_name("docx-line-match.py"))
matcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(matcher)


class LineMatchTests(unittest.TestCase):
    def test_arabic_visual_and_logical_edges(self):
        text = "دولةذاتسيادةوعضوفيالاتحاد"
        self.assertTrue(matcher.same_start(text, text[::-1]))
        self.assertTrue(matcher.same_start("نعم", "معن"))
        self.assertFalse(matcher.same_start("الاتحاد", "الفرنسية"))

    def test_missing_arabic_is_not_a_match(self):
        self.assertFalse(matcher.same_start("الاتحاد", "\0\0\0\0\0\0\0"))
        self.assertFalse(matcher.same_start("الاتحاد", "ا\0\0\0\0\0د"))

    def test_latin_order_and_existing_edge_rules(self):
        self.assertTrue(matcher.same_start("same beginning", "same changed ending"))
        self.assertFalse(matcher.same_start("abcdefgh", "hgfedcba"))
        self.assertTrue(matcher.same_start("Yes", "Yes"))
        self.assertFalse(matcher.same_start("Yes", "No"))
        self.assertFalse(matcher.same_start("abc", "abcd"))

    def test_existing_embedded_cjk_tolerance(self):
        self.assertTrue(matcher.same_start("民國臺灣", "\u2ea0國臺灣"))
        self.assertTrue(matcher.same_start("招标文件", "\0标文件"))


if __name__ == "__main__":
    unittest.main()
