function(next_runner_is_isolated config_file output_var)
  # Flutter's actual selected entry point controls both Dart and the native
  # runner. An offline build or an unrelated Dart define is not a profile flag.
  file(STRINGS "${config_file}" target_line REGEX "^[ \t]*\"FLUTTER_TARGET=")
  string(REPLACE "\\" "/" target_line "${target_line}")
  if(target_line MATCHES "\"FLUTTER_TARGET=([^\"]*/)?main_(isolated|private_manual)[.]dart\"")
    set(${output_var} TRUE PARENT_SCOPE)
  else()
    set(${output_var} FALSE PARENT_SCOPE)
  endif()
endfunction()
