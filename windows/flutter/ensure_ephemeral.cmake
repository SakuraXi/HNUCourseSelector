# 兜底脚本：确保引擎产物与资产包存在于构建目录。
# 本脚本由 windows/flutter/CMakeLists.txt 的 flutter_assemble 自定义命令调用：
#   MODE=pre  —— tool_backend 之前：补引擎文件 + 资产残缺时清缓存/从快照恢复
#   MODE=post —— tool_backend 之后：资产完整则刷新快照；仍残缺则从快照恢复
# 背景：flutter 的 assemble 缓存 stamp 与实际文件频繁失配（debug/release 混合构建、
# hot restart、插件刷新等都会触发），快照机制保证 INSTALL 拿到的永远是完整资产。

set(ENGINE_BASE "${FLUTTER_ROOT}/bin/cache/artifacts/engine/windows-x64")

# 按构建模式解析引擎产物目录（Debug 在基础目录，Release/Profile 有独立目录）
if(BUILD_MODE STREQUAL "Release")
  set(ENGINE_MODE_DIR "${FLUTTER_ROOT}/bin/cache/artifacts/engine/windows-x64-release")
elseif(BUILD_MODE STREQUAL "Profile")
  set(ENGINE_MODE_DIR "${FLUTTER_ROOT}/bin/cache/artifacts/engine/windows-x64-profile")
else()
  set(ENGINE_MODE_DIR "${ENGINE_BASE}")
endif()

set(_FA "${PROJECT_DIR}/build/flutter_assets")
if(BUILD_MODE STREQUAL "Release")
  set(_SNAP "${PROJECT_DIR}/build/flutter_assets_snapshot_release")
else()
  set(_SNAP "${PROJECT_DIR}/build/flutter_assets_snapshot_debug")
endif()

# ---- 引擎产物（wrapper 源码/头文件/DLL/导入库/ICU）----
if(MODE STREQUAL "pre")
  # wrapper 源码 + 头文件（与构建模式无关，内容一致）
  file(COPY "${ENGINE_BASE}/cpp_client_wrapper/" DESTINATION "${EPHEMERAL_DIR}/cpp_client_wrapper")
  foreach(_h flutter_export.h flutter_messenger.h flutter_plugin_registrar.h flutter_texture_registrar.h flutter_windows.h)
    file(COPY "${ENGINE_BASE}/${_h}" DESTINATION "${EPHEMERAL_DIR}")
  endforeach()

  # 引擎 DLL / 导入库：按构建模式强制覆盖（防止 Debug/Release 版本错配
  # 导致 "Not running in AOT mode" 崩溃，或链接时 LNK1181）
  file(COPY "${ENGINE_MODE_DIR}/flutter_windows.dll" DESTINATION "${EPHEMERAL_DIR}")
  file(COPY "${ENGINE_MODE_DIR}/flutter_windows.dll.lib" DESTINATION "${EPHEMERAL_DIR}")
  if(EXISTS "${ENGINE_MODE_DIR}/flutter_windows.dll.exp")
    file(COPY "${ENGINE_MODE_DIR}/flutter_windows.dll.exp" DESTINATION "${EPHEMERAL_DIR}")
  endif()

  # ICU 数据文件
  if(NOT EXISTS "${EPHEMERAL_DIR}/icudtl.dat")
    file(COPY "${ENGINE_BASE}/icudtl.dat" DESTINATION "${EPHEMERAL_DIR}")
  endif()
endif()

# ---- 资产包完整性检查 ----
# Manifest / 图标字体 / OCR 模型任一缺失即视为残缺
set(_ASSETS_OK TRUE)
foreach(_f AssetManifest.json fonts/MaterialIcons-Regular.otf assets/models/common_old.onnx)
  if(NOT EXISTS "${_FA}/${_f}")
    set(_ASSETS_OK FALSE)
  endif()
endforeach()

if(MODE STREQUAL "pre")
  if(NOT _ASSETS_OK)
    # 清空 assemble 的哈希缓存目录与 .last_build_id，强制其全量重跑
    file(REMOVE "${PROJECT_DIR}/build/.last_build_id")
    file(GLOB _cache_dirs LIST_DIRECTORIES true "${PROJECT_DIR}/build/*")
    foreach(_d ${_cache_dirs})
      get_filename_component(_n "${_d}" NAME)
      if(_n MATCHES "^[0-9a-f]{32}$")
        file(REMOVE_RECURSE "${_d}")
      endif()
    endforeach()
    # 若有快照，先恢复静态资产（assemble 万一仍异常，INSTALL 也有完整资产可用）
    if(EXISTS "${_SNAP}/AssetManifest.json")
      file(REMOVE_RECURSE "${_FA}")
      file(COPY "${_SNAP}/" DESTINATION "${_FA}")
    endif()
  endif()
else()
  # MODE=post：assemble 之后
  if(_ASSETS_OK)
    # 资产完整 → 刷新该模式的快照
    file(REMOVE_RECURSE "${_SNAP}")
    file(COPY "${_FA}/" DESTINATION "${_SNAP}")
  elseif(EXISTS "${_SNAP}/AssetManifest.json")
    # assemble 仍产出残缺资产 → 从快照恢复，保证 INSTALL 完整
    file(REMOVE_RECURSE "${_FA}")
    file(COPY "${_SNAP}/" DESTINATION "${_FA}")
  endif()
endif()
