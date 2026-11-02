# Real Kotlin SCIP fixture

Generated on 2026-10-07 with Kotlin 2.4.20 and scip-java compiler plugin source
commit `9f288dd339c7e9fc257a7b21714d9a402fd4d837`, using Radiology's
`IndexingScripts/kotlin-index.gradle` and `kotlin-index.sh`, Gradle 9.7.1,
and JDK 17. The index is actual compiler output, not a fabricated protobuf.

The three source files exercise cross-file definitions, overload identity,
an unrelated same-spelled function, and UTF-16 positions after accented text
and an emoji. The PR fixture replaces `read(1)` with the indexed `read(2)`;
the call's coordinates remain identical but the line is genuinely changed.

The index's original project root under /tmp is provenance only. Its document
paths are repository-relative and tests always resolve them against their own
temporary source roots. No real tkos code is stored here.
