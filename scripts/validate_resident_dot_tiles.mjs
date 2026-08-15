import { readFileSync } from "node:fs";
import { VectorTile } from "@mapbox/vector-tile";
import Pbf from "pbf";
import { PMTiles } from "pmtiles";

const [archivePath, expectedCountValue] = process.argv.slice(2);
if (!archivePath || !expectedCountValue) {
  throw new Error("Usage: node scripts/validate_resident_dot_tiles.mjs ARCHIVE EXPECTED_COUNT");
}

const expectedCount = Number(expectedCountValue);
if (!Number.isInteger(expectedCount) || expectedCount <= 0) {
  throw new Error(`Invalid expected resident-dot count: ${expectedCountValue}`);
}

class MemoryPmtilesSource {
  constructor(path) {
    this.path = path;
    this.bytes = readFileSync(path);
    this.tileDataOffset = Number.POSITIVE_INFINITY;
    this.maxCompressedTileBytes = 0;
  }

  getKey() {
    return this.path;
  }

  async getBytes(offset, length) {
    if (offset >= this.tileDataOffset) {
      this.maxCompressedTileBytes = Math.max(this.maxCompressedTileBytes, length);
    }
    return {
      data: this.bytes.buffer.slice(
        this.bytes.byteOffset + offset,
        this.bytes.byteOffset + offset + length,
      ),
    };
  }
}

const longitudeToTileX = (longitude, zoom) =>
  Math.floor(((longitude + 180) / 360) * 2 ** zoom);

const latitudeToTileY = (latitude, zoom) =>
  Math.floor(
    ((1 - Math.asinh(Math.tan((latitude * Math.PI) / 180)) / Math.PI) / 2) * 2 ** zoom,
  );

const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};

const source = new MemoryPmtilesSource(archivePath);
const archive = new PMTiles(source);
const header = await archive.getHeader();
source.tileDataOffset = header.tileDataOffset;
const metadata = await archive.getMetadata();

assert(header.minZoom === 8, `Resident-dot archive minzoom is ${header.minZoom}, expected 8`);
assert(header.maxZoom === 16, `Resident-dot archive maxzoom is ${header.maxZoom}, expected 16`);
assert(
  Number(metadata.tippecanoe_decisions?.droprate) === 1,
  `Resident-dot archive droprate is ${metadata.tippecanoe_decisions?.droprate}, expected 1`,
);
assert(source.bytes.byteLength < 10 * 1024 * 1024, "Resident-dot archive exceeds 10 MB");

const featureCounts = {};
let maxDecodedTileBytes = 0;
for (let zoom = header.minZoom; zoom <= header.maxZoom; zoom += 1) {
  let featureCount = 0;
  const minimumX = longitudeToTileX(header.minLon, zoom);
  const maximumX = longitudeToTileX(header.maxLon, zoom);
  const minimumY = latitudeToTileY(header.maxLat, zoom);
  const maximumY = latitudeToTileY(header.minLat, zoom);
  for (let x = minimumX; x <= maximumX; x += 1) {
    for (let y = minimumY; y <= maximumY; y += 1) {
      const response = await archive.getZxy(zoom, x, y);
      if (!response) continue;
      maxDecodedTileBytes = Math.max(maxDecodedTileBytes, response.data.byteLength);
      const tile = new VectorTile(new Pbf(new Uint8Array(response.data)));
      featureCount += tile.layers.resident_dots?.length ?? 0;
    }
  }
  featureCounts[zoom] = featureCount;
  assert(
    featureCount >= expectedCount,
    `Resident dots at zoom ${zoom}: ${featureCount}, expected at least ${expectedCount}`,
  );
}

assert(
  featureCounts[header.minZoom] === expectedCount,
  `Resident dots at zoom 8: ${featureCounts[header.minZoom]}, expected exactly ${expectedCount}`,
);
assert(source.maxCompressedTileBytes < 3 * 1024 * 1024, "A compressed resident-dot tile exceeds 3 MB");
assert(maxDecodedTileBytes < 3 * 1024 * 1024, "A decoded resident-dot tile exceeds 3 MB");

process.stdout.write(JSON.stringify({
  min_zoom: header.minZoom,
  max_zoom: header.maxZoom,
  drop_rate: Number(metadata.tippecanoe_decisions.droprate),
  archive_bytes: source.bytes.byteLength,
  maximum_compressed_tile_bytes: source.maxCompressedTileBytes,
  maximum_decoded_tile_bytes: maxDecodedTileBytes,
  feature_counts_by_zoom: featureCounts,
}));
