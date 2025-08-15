#!/bin/bash

echo "Creating optimized GeoLambda layer..."

# Create temporary directory for optimization
TEMP_DIR="/tmp/geolambda_opt"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Extract the original layer
echo "Extracting original layer..."
unzip -q geolambda-modern.zip -d "$TEMP_DIR"

cd "$TEMP_DIR"

# Get original size
ORIGINAL_SIZE=$(du -sh . | cut -f1)
echo "Original size: $ORIGINAL_SIZE"

echo "Removing unnecessary components..."

# 1. Remove the largest unnecessary files
echo "  - Removing static libraries (.a files)..."
find . -name "*.a" -delete

echo "  - Removing PostgreSQL binaries (not needed for GDAL raster operations)..."
rm -f bin/postgres* bin/pg_* bin/ecpg* bin/initdb bin/createdb bin/dropdb bin/psql
rm -rf lib/postgresql/

echo "  - Removing CryptoPP test executable..."
rm -f bin/cryptest.exe

echo "  - Removing development headers and pkgconfig files..."
rm -rf include/
rm -rf lib/pkgconfig/
rm -rf share/pkgconfig/

echo "  - Removing man pages and documentation..."
rm -rf share/man/
rm -rf share/doc/

echo "  - Removing unnecessary HDF4/HDF5 tools (keeping libraries)..."
rm -f bin/h4* bin/h5* bin/hdf*

echo "  - Removing TIFF utilities (keeping libtiff)..."
rm -f bin/tiff* bin/fax2tiff bin/pal2rgb bin/ppm2tiff bin/raw2tiff bin/rgb2ycbcr bin/thumbnail

echo "  - Removing other utility binaries not needed for raster tile generation..."
rm -f bin/curl* bin/xml2* bin/xmllint bin/xmlcatalog
rm -f bin/pkg-config* bin/libpng* bin/pngfix
rm -f bin/unzstd bin/zstd* 
rm -f bin/nearblack  # GDAL utility not needed for basic raster operations

# Keep only essential GDAL binaries for your use case
echo "  - Keeping only essential GDAL binaries..."
mkdir -p bin_keep
# Essential for your generateRasterTileSet.py function
cp bin/gdal_translate bin_keep/ 2>/dev/null || echo "    Warning: gdal_translate not found"
cp bin/gdalinfo bin_keep/ 2>/dev/null || echo "    Warning: gdalinfo not found"
cp bin/gdalwarp bin_keep/ 2>/dev/null || echo "    Warning: gdalwarp not found"
cp bin/gdal-config bin_keep/ 2>/dev/null || echo "    Warning: gdal-config not found"
cp bin/geos-config bin_keep/ 2>/dev/null || echo "    Warning: geos-config not found"
cp bin/proj* bin_keep/ 2>/dev/null || echo "    Warning: proj binaries not found"

# Remove all other binaries and replace with essentials
rm -rf bin/
mv bin_keep bin/

echo "  - Stripping debug symbols from libraries..."
find lib/ -name "*.so*" -type f -exec strip --strip-debug {} \; 2>/dev/null || echo "    Warning: strip command failed on some files"

echo "  - Removing duplicate library symlinks (keeping only .so files)..."
# Remove versioned symlinks, keep only the main .so files and one version
find lib/ -name "*.so.*.*.*" -delete
find lib/ -name "*.so.*.*" -not -name "*.so.200*" -not -name "*.so.34*" -not -name "*.so.25*" -not -name "*.so.1*" -not -name "*.so.6*" -not -name "*.so.3*" -delete

# Get optimized size
OPTIMIZED_SIZE=$(du -sh . | cut -f1)
echo "Optimized size: $OPTIMIZED_SIZE"

# Create optimized layer zip
echo "Creating optimized layer zip..."
zip -r9q /tmp/geolambda-optimized.zip .

# Copy back to original location
cp /tmp/geolambda-optimized.zip /Users/axsj/dev/docker-lambda/geolambda-optimized.zip

cd /Users/axsj/dev/docker-lambda

# Show size comparison
ORIGINAL_ZIP_SIZE=$(ls -lh geolambda-modern.zip | awk '{print $5}')
OPTIMIZED_ZIP_SIZE=$(ls -lh geolambda-optimized.zip | awk '{print $5}')

echo ""
echo "=== SIZE COMPARISON ==="
echo "Original layer:  $ORIGINAL_ZIP_SIZE"
echo "Optimized layer: $OPTIMIZED_ZIP_SIZE"
echo ""
echo "Optimization complete! Optimized layer saved as: geolambda-optimized.zip"

# Cleanup
rm -rf "$TEMP_DIR"
