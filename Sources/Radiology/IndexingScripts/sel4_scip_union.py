"""Union SCIP compiler output without losing configuration-specific documents.

Unknown protobuf fields are preserved. Local symbols are reconciled only by
their compiler-reported definition coordinates in the same original document;
locals without definitions remain specific to their input index.
"""

import hashlib


def varint(value):
    result = bytearray()
    while value > 127:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def fields(data):
    offset = 0

    def integer():
        nonlocal offset
        value = shift = 0
        while True:
            byte = data[offset]
            offset += 1
            value |= (byte & 127) << shift
            if byte < 128:
                return value
            shift += 7
            if shift > 70:
                raise ValueError("Invalid protobuf varint")

    while offset < len(data):
        tag = integer()
        number, wire = tag >> 3, tag & 7
        if wire == 0:
            value = integer()
        elif wire in (1, 2, 5):
            size = integer() if wire == 2 else (8 if wire == 1 else 4)
            value = data[offset:offset + size]
            if len(value) != size:
                raise ValueError("Truncated protobuf field")
            offset += size
        else:
            raise ValueError("Unsupported protobuf wire type: " + str(wire))
        yield number, wire, value


def message(items):
    result = bytearray()
    for number, wire, value in items:
        result += varint((number << 3) | wire)
        if wire == 0:
            result += varint(value)
        else:
            if wire == 2:
                result += varint(len(value))
            result += value
    return bytes(result)


def value_of(items, number, default=b""):
    return next((v for n, _, v in items if n == number), default)


def union(indexes):
    metadata = None
    documents = {}
    external = set()
    unknown = set()
    for data in indexes:
        origin = hashlib.sha256(data).digest()
        for number, wire, value in fields(data):
            if number == 1:
                metadata = metadata or value
            elif number == 3:
                external.add(value)
            elif number == 2:
                doc = list(fields(value))
                path = value_of(doc, 1)
                occurrences = [list(fields(v)) for n, _, v in doc if n == 2]
                definitions = {}
                for occurrence in occurrences:
                    symbol = value_of(occurrence, 2)
                    if symbol.startswith(b"local ") and value_of(occurrence, 3, 0) & 1:
                        ranges = message((n, w, v) for n, w, v in occurrence if n in (1, 8, 9))
                        definitions.setdefault(symbol, set()).add(ranges)
                locals_map = {}

                def remap(symbol):
                    if not symbol.startswith(b"local "):
                        return symbol
                    if symbol not in locals_map:
                        locations = definitions.get(symbol)
                        key = b"\0".join([path, *sorted(locations)]) if locations else b"\0".join([origin, path, symbol])
                        locals_map[symbol] = b"local " + str(int.from_bytes(hashlib.sha256(key).digest()[:16], "big")).encode()
                    return locals_map[symbol]

                # Common document metadata must agree across configurations.
                attributes = {(n, w, v) for n, w, v in doc if n not in (2, 3)}
                merged = documents.setdefault(path, [attributes, set(), {}])
                if attributes != merged[0]:
                    raise ValueError("Incompatible document metadata for " + path.decode())
                for occurrence in occurrences:
                    merged[1].add(message((n, w, remap(v) if n == 2 else v) for n, w, v in occurrence))
                for n, _, info in doc:
                    if n != 3:
                        continue
                    items = list(fields(info))
                    rewritten = []
                    for k, w, v in items:
                        if k == 1:
                            v = remap(v)
                        elif k == 4:
                            v = message((a, b, remap(c) if a == 1 else c) for a, b, c in fields(v))
                        rewritten.append((k, w, v))
                    symbol = value_of(rewritten, 1)
                    encoded = message(rewritten)
                    if len(encoded) > len(merged[2].get(symbol, b"")):
                        merged[2][symbol] = encoded
            else:
                unknown.add((number, wire, value))
    if metadata is None:
        raise ValueError("No SCIP metadata")
    result = [(1, 2, metadata)]
    for path in sorted(documents):
        attributes, occurrences, symbols = documents[path]
        result.append((2, 2, message([*sorted(attributes),
            *((2, 2, v) for v in sorted(occurrences)), *((3, 2, symbols[k]) for k in sorted(symbols))])))
    result.extend((3, 2, v) for v in sorted(external))
    result.extend(sorted(unknown))
    return message(result)
