

<!-- markdownlint-disable MD033 -->
<p align="center">
  <img src="https://user-images.githubusercontent.com/10407788/95621320-7b226080-0a3f-11eb-8194-4b55a5555836.png" style="max-width: 800px;" alt="docker-lambda"></a>
</p>
<p align="center">
  <b>Amazonlinux Docker images and AWS Lambda layers with GDAL.</b>
</p>
<p align="center">
  <a href="https://github.com/lambgeo/docker-lambda/actions?query=workflow%3ACI" target="_blank">
      <img src="https://github.com/lambgeo/docker-lambda/workflows/CI/badge.svg" alt="Test">
  </a>
</p>
<!-- markdownlint-enable -->

# Docker Images

Based on `public.ecr.aws/lambda/provided:al2` (AmazonLinux 2)

- GDAL 3.8.3
  - **ghcr.io/lambgeo/lambda-gdal:3.8** (Fev 2024)

Runtimes images:

- Python (based on `public.ecr.aws/lambda/python:{version}`)
  - **ghcr.io/lambgeo/lambda-gdal:3.8-python3.9**
  - **ghcr.io/lambgeo/lambda-gdal:3.8-python3.10**
  - **ghcr.io/lambgeo/lambda-gdal:3.8-python3.11**

**archived**
  - **ghcr.io/lambgeo/lambda-gdal:3.6**
  - **ghcr.io/lambgeo/lambda-gdal:3.6-python3.9**
  - **ghcr.io/lambgeo/lambda-gdal:3.6-python3.10**
  - **ghcr.io/lambgeo/lambda-gdal:3.6-python3.11**

see: <https://github.com/lambgeo/docker-lambda/pkgs/container/lambda-gdal>

# Creating Lambda Layers

This repository helps you create your own optimized GDAL Lambda layers. Instead of using pre-built layers, you can build and customize layers specifically for your needs.

**Why create your own layers?**
- **Size optimization**: Reduce from 138MB to 52MB by removing unused components
- **Customization**: Include only the GDAL tools and libraries you need
- **Version control**: Use the exact GDAL version your application requires
- **No external dependencies**: Full control over your layer content

# Creating Optimized Lambda Layers for Raster Tile Generation

This section explains how to create optimized GDAL Lambda layers specifically for raster tile generation workflows, reducing layer size from 138MB to ~52MB while maintaining all necessary functionality.

## Quick Start: Build and Optimize Layer

### 1. Build the Docker Image

```bash
# Build GDAL 3.8.3 image for Python 3.9
./scripts/build.sh 3.8.3 python 3.9
```

### 2. Extract Layer from Docker Image

```bash
# Create container to extract layer contents
docker run --name gdal-extract -d ghcr.io/lambgeo/lambda-gdal:3.8-python3.9 tail -f /dev/null

# Create layer zip with all GDAL components
docker exec gdal-extract bash -c "
cd /opt && 
zip -r9q --symlinks /tmp/geolambda-modern.zip \
  bin/ lib/*.so* share/gdal/ share/proj/
"

# Copy layer zip to host
docker cp gdal-extract:/tmp/geolambda-modern.zip ./geolambda-modern.zip

# Cleanup
docker stop gdal-extract
docker rm gdal-extract
```

### 3. Optimize Layer Size

Use the provided optimization script to reduce layer size by ~62%:

```bash
# Run optimization script
./optimize_layer.sh
```

This creates `geolambda-optimized.zip` (52MB) from the original (138MB).

## What Gets Optimized?

### Removed (Safe for Raster Operations):
- ✂️ **Static libraries (.a files)**: 107MB+ (libcryptopp.a, libxml2.a)
- ✂️ **PostgreSQL binaries**: ~20MB (postgres, pg_*, ecpg)
- ✂️ **CryptoPP test executables**: 66MB (cryptest.exe)
- ✂️ **Development headers**: include/ directory
- ✂️ **Documentation**: man pages, doc files
- ✂️ **Unnecessary tools**: HDF utilities, TIFF utilities, curl tools
- ✂️ **Debug symbols**: Stripped from all .so files
- ✂️ **Duplicate symlinks**: Extra versioned library files

### Kept (Essential):
- ✅ **Core GDAL binaries**: `gdal_translate`, `gdalinfo`, `gdalwarp`
- ✅ **Configuration tools**: `gdal-config`, `geos-config`
- ✅ **PROJ tools**: `proj`, `projinfo`, `projsync`
- ✅ **All shared libraries**: `libgdal.so` (30MB), `libproj.so` (4.6MB), `libgeos.so` (4.5MB)
- ✅ **Data directories**: `share/gdal/`, `share/proj/` with all coordinate systems

## Using with Raster Tile Generation

### Layer Structure
```text
geolambda-optimized.zip (52MB)
  |
  |___ bin/
  |    |___ gdal_translate    # PNG → GeoTIFF conversion
  |    |___ gdalinfo          # Image dimension detection
  |    |___ gdalwarp          # Raster warping/reprojection
  |    |___ gdal-config       # GDAL configuration
  |    |___ proj*             # Coordinate system tools
  |
  |___ lib/
  |    |___ libgdal.so        # GDAL library (30MB)
  |    |___ libproj.so        # PROJ library (4.6MB)
  |    |___ libgeos.so        # GEOS library (4.5MB)
  |    |___ [other deps]      # Supporting libraries
  |
  |___ share/
       |___ gdal/            # GDAL data files
       |___ proj/            # PROJ coordinate system database
```

### Lambda Function Implementation

Your Lambda function should set up the environment and use GDAL tools via subprocess:

```python
import os
import subprocess

# Layer paths (automatically available at /opt/ when layer is attached)
LAYER_BIN = "/opt/bin"
LAYER_LIB = "/opt/lib"
LAYER_SHARE_GDAL = "/opt/share/gdal"
LAYER_SHARE_PROJ = "/opt/share/proj"

def handler(event, context):
    # Configure GDAL environment variables
    os.environ['GDAL_DATA'] = LAYER_SHARE_GDAL
    os.environ['PROJ_LIB'] = LAYER_SHARE_PROJ
    os.environ['LD_LIBRARY_PATH'] = f"{LAYER_LIB}:{os.environ.get('LD_LIBRARY_PATH','')}"
    os.environ['PATH'] = f"{LAYER_BIN}:{os.environ.get('PATH','')}"
    
    print("GDAL environment configured:")
    print(f"  GDAL_DATA: {os.environ['GDAL_DATA']}")
    print(f"  PROJ_LIB: {os.environ['PROJ_LIB']}")
    
    # Example: Convert PNG to georeferenced GeoTIFF
    input_image = "/tmp/input.png"
    output_geotiff = "/tmp/output.tif"
    
    # Define geographic bounds (example coordinates)
    minx, miny, maxx, maxy = -122.5, 37.7, -122.3, 37.8
    
    # Use gdal_translate to create georeferenced GeoTIFF
    gdal_translate_cmd = [
        f"{LAYER_BIN}/gdal_translate",
        "-of", "GTiff",
        "-a_srs", "EPSG:4326",  # WGS84 coordinates
        "-a_ullr", f"{minx}", f"{maxy}", f"{maxx}", f"{miny}",
        input_image,
        output_geotiff
    ]
    
    try:
        result = subprocess.run(gdal_translate_cmd, check=True, 
                              capture_output=True, text=True)
        print(f"Successfully created GeoTIFF: {output_geotiff}")
        return {"success": True}
    except subprocess.CalledProcessError as e:
        print(f"GDAL error: {e.stderr}")
        return {"success": False, "error": str(e)}
```

### AWS Lambda Configuration

**Layer Setup:**
1. Upload `geolambda-optimized.zip` as a Lambda Layer
2. Note the layer ARN
3. Attach layer to your Lambda function

**Environment Variables (Optional):**
The function can set these programmatically, but you can also set them in Lambda config:
```
GDAL_DATA=/opt/share/gdal
PROJ_LIB=/opt/share/proj
```

**Function Configuration:**
- Runtime: Python 3.9 (matches layer build)
- Timeout: 5+ minutes (for tile generation)
- Memory: 1024MB+ (depending on image sizes)
- Layers: [your-layer-arn]

### Real-World Example: Raster Tile Set Generation

For a complete example of using this layer for generating map tile pyramids, see the pattern used in production raster tile generation functions:

1. **Image Preparation**: Use `gdal_translate` to convert PNG/JPG to georeferenced GeoTIFF
2. **Dimension Detection**: Use `gdalinfo` to get image dimensions safely
3. **Tile Generation**: Create tile pyramids using custom tiling logic or GDAL tools
4. **Environment Handling**: Set up clean library paths to avoid glibc conflicts

The optimized layer provides all necessary components while staying under AWS Lambda's size limits, making it perfect for serverless geospatial processing workflows.

### Benefits of This Approach

- ✅ **Size Optimized**: 52MB vs 138MB (62% reduction)
- ✅ **Lambda Compatible**: Under AWS size limits
- ✅ **Production Ready**: Includes all essential GDAL/PROJ functionality
- ✅ **Subprocess Safe**: Works reliably with subprocess calls
- ✅ **Memory Efficient**: Stripped debug symbols and removed unused components
- ✅ **Coordinate System Support**: Full PROJ database for all projections
