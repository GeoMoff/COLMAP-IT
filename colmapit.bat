@echo off
setlocal

:: --- CONFIGURATION START ---
:: UPDATE THIS LINE to point to your colmap.exe
set "COLMAP_EXE=C:\LF\COLMAP\bin\colmap.exe"
:: --- CONFIGURATION END ---

:: 1. Self-Check: Does COLMAP exist?
if not exist "%COLMAP_EXE%" (
    echo [CRITICAL ERROR] COLMAP not found at: "%COLMAP_EXE%"
    pause
    exit /b
)

:: 2. Check if a folder was dragged
if "%~1"=="" (
    echo [ERROR] No folder detected.
    echo Usage: Drag and drop your project folder onto this file.
    pause
    exit /b
)

set "PROJECT_PATH=%~1"
set "DB_PATH=%PROJECT_PATH%\database.db"

:: 3. INTELLIGENT IMAGE DETECTION
if exist "%PROJECT_PATH%\images" (
    echo [INFO] Detected 'images' subfolder. Using it.
    set "IMAGE_DIR=%PROJECT_PATH%\images"
) else (
    echo [INFO] No 'images' subfolder found. Using root folder.
    set "IMAGE_DIR=%PROJECT_PATH%"
)

:: Clean up previous run if present
if exist "%DB_PATH%" (
    echo [INFO] Removing previous database.db for clean run...
    del "%DB_PATH%"
)

echo ----------------------------------------------------
echo Project: %PROJECT_PATH%
echo Images:  %IMAGE_DIR%
echo Output:  %PROJECT_PATH%\sparse
echo ----------------------------------------------------

:: 4. Feature Extraction (GPU)
:: Note: COLMAP uses full resolution by default. No max_image_size needed.
:: SIMPLE_RADIAL + single_camera is correct for a single device capture set.
echo.
echo [1/3] Extracting Features...
"%COLMAP_EXE%" feature_extractor ^
    --database_path "%DB_PATH%" ^
    --image_path "%IMAGE_DIR%" ^
    --ImageReader.camera_model SIMPLE_RADIAL ^
    --ImageReader.single_camera 1 ^
    --SiftExtraction.max_num_features 8192

:: Error Check 1
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Feature extraction failed.
    echo Please check the error message above.
    pause
    exit /b
)

:: 5. Feature Matching (GPU)
echo.
echo [2/3] Matching Features...
"%COLMAP_EXE%" exhaustive_matcher ^
    --database_path "%DB_PATH%"

:: Error Check 2
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Feature matching failed.
    pause
    exit /b
)

:: 6. Sparse Reconstruction
if not exist "%PROJECT_PATH%\sparse" mkdir "%PROJECT_PATH%\sparse"

echo.
echo [3/3] Creating Sparse Point Cloud...
"%COLMAP_EXE%" mapper ^
    --database_path "%DB_PATH%" ^
    --image_path "%IMAGE_DIR%" ^
    --output_path "%PROJECT_PATH%\sparse" ^
    --Mapper.ba_global_max_num_iterations 50

:: Error Check 3
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Mapper failed. Try with fewer images or check image overlap/lighting.
    pause
    exit /b
)

echo.
echo ----------------------------------------------------
echo VERIFYING OUTPUT...

set "SPARSE_MODEL=%PROJECT_PATH%\sparse\0"
set "ALL_OK=1"

if exist "%SPARSE_MODEL%\cameras.bin" (
    echo [OK] cameras.bin found.
) else (
    echo [MISSING] cameras.bin
    set "ALL_OK=0"
)

if exist "%SPARSE_MODEL%\images.bin" (
    echo [OK] images.bin found.
) else (
    echo [MISSING] images.bin
    set "ALL_OK=0"
)

if exist "%SPARSE_MODEL%\points3D.bin" (
    echo [OK] points3D.bin found.
) else (
    echo [MISSING] points3D.bin
    set "ALL_OK=0"
)

echo.
if "%ALL_OK%"=="1" (
    echo ====================================================
    echo SUCCESS! All output files verified.
    echo You can now drag "%PROJECT_PATH%" into LichtFeld Studio.
    echo ====================================================
    echo.
    :: Show model stats
    echo Generating model statistics...
    "%COLMAP_EXE%" model_analyzer --path "%SPARSE_MODEL%" 2>nul
) else (
    echo [ERROR] One or more .bin files were NOT created.
    echo This usually means the mapper failed to reconstruct.
    echo Tips:
    echo   - Ensure images have good overlap (60-80%%)
    echo   - Check lighting consistency
    echo   - Try with fewer or more images
    echo   - Look for additional sparse\1, sparse\2 sub-models
)
echo ----------------------------------------------------
pause
