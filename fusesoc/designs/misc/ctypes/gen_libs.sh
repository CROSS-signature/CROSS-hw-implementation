#!/usr/bin/env bash
VERSIONS="RSDP RSDPG"
CATEGORIES="CATEGORY_1 CATEGORY_3 CATEGORY_5"
CORNERS="SPEED BALANCED SIG_SIZE"

for ver in $VERSIONS; do
    for cat in $CATEGORIES; do
        for cor in $CORNERS; do
            echo libcross_${ver}_${cat}_${cor}.so
            make version=${ver} category=${cat} corner=${cor}
            mv libcross.so libcross_${ver}_${cat}_${cor}.so
        done
    done
done
