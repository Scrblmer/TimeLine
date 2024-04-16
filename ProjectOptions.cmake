include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(TimeLine_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(TimeLine_setup_options)
  option(TimeLine_ENABLE_HARDENING "Enable hardening" ON)
  option(TimeLine_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    TimeLine_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    TimeLine_ENABLE_HARDENING
    OFF)

  TimeLine_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR TimeLine_PACKAGING_MAINTAINER_MODE)
    option(TimeLine_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(TimeLine_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(TimeLine_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(TimeLine_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(TimeLine_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(TimeLine_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(TimeLine_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(TimeLine_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(TimeLine_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(TimeLine_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(TimeLine_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(TimeLine_ENABLE_PCH "Enable precompiled headers" OFF)
    option(TimeLine_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(TimeLine_ENABLE_IPO "Enable IPO/LTO" ON)
    option(TimeLine_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(TimeLine_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(TimeLine_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(TimeLine_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(TimeLine_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(TimeLine_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(TimeLine_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(TimeLine_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(TimeLine_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(TimeLine_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(TimeLine_ENABLE_PCH "Enable precompiled headers" OFF)
    option(TimeLine_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      TimeLine_ENABLE_IPO
      TimeLine_WARNINGS_AS_ERRORS
      TimeLine_ENABLE_USER_LINKER
      TimeLine_ENABLE_SANITIZER_ADDRESS
      TimeLine_ENABLE_SANITIZER_LEAK
      TimeLine_ENABLE_SANITIZER_UNDEFINED
      TimeLine_ENABLE_SANITIZER_THREAD
      TimeLine_ENABLE_SANITIZER_MEMORY
      TimeLine_ENABLE_UNITY_BUILD
      TimeLine_ENABLE_CLANG_TIDY
      TimeLine_ENABLE_CPPCHECK
      TimeLine_ENABLE_COVERAGE
      TimeLine_ENABLE_PCH
      TimeLine_ENABLE_CACHE)
  endif()

  TimeLine_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (TimeLine_ENABLE_SANITIZER_ADDRESS OR TimeLine_ENABLE_SANITIZER_THREAD OR TimeLine_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(TimeLine_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(TimeLine_global_options)
  if(TimeLine_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    TimeLine_enable_ipo()
  endif()

  TimeLine_supports_sanitizers()

  if(TimeLine_ENABLE_HARDENING AND TimeLine_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR TimeLine_ENABLE_SANITIZER_UNDEFINED
       OR TimeLine_ENABLE_SANITIZER_ADDRESS
       OR TimeLine_ENABLE_SANITIZER_THREAD
       OR TimeLine_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${TimeLine_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${TimeLine_ENABLE_SANITIZER_UNDEFINED}")
    TimeLine_enable_hardening(TimeLine_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(TimeLine_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(TimeLine_warnings INTERFACE)
  add_library(TimeLine_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  TimeLine_set_project_warnings(
    TimeLine_warnings
    ${TimeLine_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(TimeLine_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    TimeLine_configure_linker(TimeLine_options)
  endif()

  include(cmake/Sanitizers.cmake)
  TimeLine_enable_sanitizers(
    TimeLine_options
    ${TimeLine_ENABLE_SANITIZER_ADDRESS}
    ${TimeLine_ENABLE_SANITIZER_LEAK}
    ${TimeLine_ENABLE_SANITIZER_UNDEFINED}
    ${TimeLine_ENABLE_SANITIZER_THREAD}
    ${TimeLine_ENABLE_SANITIZER_MEMORY})

  set_target_properties(TimeLine_options PROPERTIES UNITY_BUILD ${TimeLine_ENABLE_UNITY_BUILD})

  if(TimeLine_ENABLE_PCH)
    target_precompile_headers(
      TimeLine_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(TimeLine_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    TimeLine_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(TimeLine_ENABLE_CLANG_TIDY)
    TimeLine_enable_clang_tidy(TimeLine_options ${TimeLine_WARNINGS_AS_ERRORS})
  endif()

  if(TimeLine_ENABLE_CPPCHECK)
    TimeLine_enable_cppcheck(${TimeLine_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(TimeLine_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    TimeLine_enable_coverage(TimeLine_options)
  endif()

  if(TimeLine_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(TimeLine_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(TimeLine_ENABLE_HARDENING AND NOT TimeLine_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR TimeLine_ENABLE_SANITIZER_UNDEFINED
       OR TimeLine_ENABLE_SANITIZER_ADDRESS
       OR TimeLine_ENABLE_SANITIZER_THREAD
       OR TimeLine_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    TimeLine_enable_hardening(TimeLine_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
