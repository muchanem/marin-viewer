import unittest
from scip_union import fields, message, union, value_of


def occurrence(symbol, line, definition=False):
    return message([(1, 2, bytes([line, 0, 3])), (2, 2, symbol), (3, 0, int(definition))])


def index(occurrences):
    return message([(1, 2, b""), (2, 2, message([
        (1, 2, b"src/a.c"), (4, 2, b"c"),
        *((2, 2, o) for o in occurrences)]))])


def occurrences(data):
    document = next(v for n, _, v in fields(data) if n == 2)
    return [list(fields(v)) for n, _, v in fields(document) if n == 2]


class SCIPUnionTests(unittest.TestCase):
    def test_conditional_definitions_are_unioned_and_identical_records_deduplicate(self):
        common = occurrence(b"cxx . . $ common().", 1, True)
        a = index([common, occurrence(b"cxx . . $ normal().", 2, True)])
        b = index([common, occurrence(b"cxx . . $ mcs().", 3, True)])
        merged = union([a, b])
        self.assertEqual(len(occurrences(merged)), 3)
        self.assertEqual(merged, union([b, a]))

    def test_local_numbers_cannot_conflate_different_definitions(self):
        a = index([occurrence(b"local 0", 1, True), occurrence(b"local 0", 2)])
        b = index([occurrence(b"local 0", 3, True), occurrence(b"local 0", 4)])
        result = occurrences(union([a, b]))
        symbols = {value_of(o, 2) for o in result}
        self.assertEqual(len(symbols), 2)
        for symbol in symbols:
            matching = [o for o in result if value_of(o, 2) == symbol]
            self.assertEqual(len(matching), 2)
            self.assertEqual(sum(value_of(o, 3, 0) & 1 for o in matching), 1)

    def test_local_numbers_reconcile_only_at_identical_definitions(self):
        a = index([occurrence(b"local 1", 1, True), occurrence(b"local 1", 2)])
        b = index([occurrence(b"local 90", 1, True), occurrence(b"local 90", 2)])
        self.assertEqual(len(occurrences(union([a, b]))), 2)

    def test_missing_local_definitions_stay_separate(self):
        a = index([occurrence(b"local 1", 2)])
        b = index([occurrence(b"local 1", 2), occurrence(b"global", 4)])
        result = occurrences(union([a, b]))
        self.assertEqual(len({value_of(o, 2) for o in result}), 3)

    def test_conflicting_coordinate_encodings_are_rejected(self):
        a = index([occurrence(b"global", 2)])
        b = message([(1, 2, b""), (2, 2, message([
            (1, 2, b"src/a.c"), (4, 2, b"c"), (6, 0, 2)]))])
        with self.assertRaises(ValueError):
            union([a, b])


if __name__ == "__main__":
    unittest.main()
