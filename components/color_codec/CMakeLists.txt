cmake_minimum_required(VERSION 3.22)
project(viadrop_color_probe LANGUAGES C CXX)
if(NOT DEFINED CIMBAR_SOURCE)
  message(FATAL_ERROR "Pass pinned CIMBAR_SOURCE")
endif()
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(DISABLE_TESTS TRUE)
if(ANDROID)
  # Android libc++ already supplies std::filesystem; libstdc++fs is a host lib.
  set(CPPFILESYSTEM "")
  # API 23 needs emulated TLS. Carry the choice through both compilation
  # and the LTO link backend (not just the individual source files).
  add_compile_options(-femulated-tls)
endif()
add_subdirectory("${CIMBAR_SOURCE}" upstream)
if(ANDROID)
  # The upstream project enables IPO on its targets. ARM32 LTO lowers its
  # thread_local config to unsupported ELF TLS even with emutls requested.
  # Compile native objects instead; ordinary Release optimizations remain on.
  foreach(part cimb_translator extractor correct_static wirehair zstd
               zstd-compress zstd-common zstd-decompress
               correct-reed-solomon correct-convolutional)
    if(TARGET ${part})
      set_property(TARGET ${part} PROPERTY INTERPROCEDURAL_OPTIMIZATION FALSE)
    endif()
  endforeach()
endif()
add_library(viadrop_color_codec STATIC codec.cpp)
target_include_directories(viadrop_color_codec PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}" PRIVATE "${CIMBAR_SOURCE}/src/lib" "${CIMBAR_SOURCE}/src/third_party_lib" ${OpenCV_INCLUDE_DIRS})
find_package(OpenCV REQUIRED)
target_include_directories(viadrop_color_codec PRIVATE ${OpenCV_INCLUDE_DIRS})
target_link_libraries(viadrop_color_codec PUBLIC cimb_translator extractor correct_static wirehair zstd opencv_core opencv_imgproc opencv_calib3d opencv_imgcodecs opencv_photo)
if(NOT ANDROID)
  target_link_libraries(viadrop_color_codec PUBLIC stdc++fs)
endif()
if(NOT ANDROID)
  add_executable(color_adapter_test test.cpp)
  target_link_libraries(color_adapter_test PRIVATE viadrop_color_codec)
  find_package(JNI REQUIRED)
endif()
add_library(viadrop_color_jni SHARED jni.cpp)
target_include_directories(viadrop_color_jni PRIVATE ${JNI_INCLUDE_DIRS})
target_link_libraries(viadrop_color_jni PRIVATE viadrop_color_codec)

if(ANDROID)
  target_link_options(viadrop_color_jni PRIVATE -femulated-tls "-Wl,-z,max-page-size=16384")
endif()
