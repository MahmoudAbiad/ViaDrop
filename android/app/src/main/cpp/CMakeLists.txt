cmake_minimum_required(VERSION 3.22.1)
project(viadrop_audio)
add_library(viadrop_audio SHARED bridge.cpp ofdm_codec.cpp ggwave-src/ggwave.cpp
  cyrinx/cyrinx_bulk.c cyrinx/cyrinx_fft.c
  cyrinx/kissfft/kiss_fft.c cyrinx/kissfft/kiss_fftr.c)
target_include_directories(viadrop_audio PRIVATE include ggwave-src cyrinx/include cyrinx/kissfft)
target_compile_features(viadrop_audio PRIVATE cxx_std_17)
target_compile_options(viadrop_audio PRIVATE -O2)
target_link_options(viadrop_audio PRIVATE "-Wl,-z,max-page-size=16384")

target_compile_definitions(viadrop_audio PRIVATE kiss_fft_scalar=double)
set_property(TARGET viadrop_audio PROPERTY C_STANDARD 11)

# Separately licensed component; dependency pins are prepared before Gradle.
if(DEFINED CIMBAR_SOURCE)
  add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../../../../components/color_codec" "viadrop-color")
endif()
