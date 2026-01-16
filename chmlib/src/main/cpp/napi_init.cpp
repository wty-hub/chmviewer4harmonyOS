#include "napi/native_api.h"
#include <string>
#include <vector>
#include <hilog/log.h>
#include "chmlib_src/chm_lib.h"

// 定义日志标签
#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0000
#define LOG_TAG "ChmLibNative"

// -------------------------------------------------------------------------
// 辅助函数：将 napi_value 转换为 std::string
// -------------------------------------------------------------------------
std::string NapiValueToString(napi_env env, napi_value value) {
    size_t size;
    // 第一次调用获取长度
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &size) != napi_ok) {
        return "";
    }
    std::string result(size + 1, '\0');
    // 第二次调用获取内容
    napi_get_value_string_utf8(env, value, &result[0], size + 1, &size);
    result.resize(size); // 去除末尾空字符
    return result;
}

// -------------------------------------------------------------------------
// 核心接口：读取 CHM 内部文件内容
// 参数 1 (String): CHM 文件在沙箱中的绝对路径 (e.g., /data/.../files/test.chm)
// 参数 2 (String): CHM 内部文件的路径 (e.g., /index.html)
// 返回值: ArrayBuffer (文件内容) 或 undefined (失败)
// -------------------------------------------------------------------------
static napi_value ReadChmFileContent(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};

    // 1. 获取入参
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 2. 参数校验
    if (argc < 2) {
        napi_throw_error(env, nullptr, "Arguments missing: path, internalPath");
        return nullptr;
    }

    std::string chmPath = NapiValueToString(env, args[0]);
    std::string innerPath = NapiValueToString(env, args[1]);

    // 3. 打开 CHM 文件
    struct chmFile *h = chm_open(chmPath.c_str());
    if (h == nullptr) {
        OH_LOG_ERROR(LOG_APP, "Failed to open CHM file: %{public}s", chmPath.c_str());
        // 返回 undefined 表示打开失败
        napi_value result;
        napi_get_undefined(env, &result);
        return result;
    }

    // 4. 解析内部文件 (Resolve Object)
    struct chmUnitInfo ui;
    // chmlib 要求内部路径通常以 '/' 开头
    if (innerPath.empty() || innerPath[0] != '/') {
        innerPath = "/" + innerPath;
    }

    int resolveStatus = chm_resolve_object(h, innerPath.c_str(), &ui);
    
    if (resolveStatus != CHM_RESOLVE_SUCCESS) {
        OH_LOG_ERROR(LOG_APP, "Failed to resolve file inside CHM: %{public}s", innerPath.c_str());
        chm_close(h);
        napi_value result;
        napi_get_undefined(env, &result);
        return result;
    }

    // 5. 准备返回数据 (ArrayBuffer)
    void *dataPtr = nullptr;
    napi_value arrayBuffer = nullptr;
    // 创建指定大小的 ArrayBuffer，dataPtr 会指向这块内存
    napi_status status = napi_create_arraybuffer(env, ui.length, &dataPtr, &arrayBuffer);

    if (status != napi_ok || dataPtr == nullptr) {
        OH_LOG_ERROR(LOG_APP, "Failed to allocate memory for file content");
        chm_close(h);
        return nullptr;
    }

    // 6. 读取数据 (Retrieve Object) 直接读入 ArrayBuffer 的内存中
    // chm_retrieve_object(handle, unit_info, buffer, offset, length)
    long long bytesRead = chm_retrieve_object(h, &ui, (unsigned char *)dataPtr, 0, ui.length);

    if (bytesRead == 0) {
        OH_LOG_WARN(LOG_APP, "Read 0 bytes from CHM object");
    }

    // 7. 清理资源
    chm_close(h);

    // 8. 返回 ArrayBuffer
    return arrayBuffer;
}

// -------------------------------------------------------------------------
// 枚举功能回调 (extern "C" 确保 C 链接兼容性)
// -------------------------------------------------------------------------
extern "C" int EnumeratorCallback(struct chmFile *h, struct chmUnitInfo *ui, void *context) {
    // We only collect paths that are not empty
    if (ui->path[0] != '\0') {
         std::vector<std::string>* paths = (std::vector<std::string>*)context;
         paths->push_back(std::string(ui->path));
    }
    return CHM_ENUMERATOR_CONTINUE;
}

// -------------------------------------------------------------------------
// 核心接口：获取 CHM 内部所有文件列表
// 参数 1 (String): CHM 文件在沙箱中的绝对路径
// 返回值: Array<String> (文件路径列表)
// -------------------------------------------------------------------------
static napi_value GetFileList(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "Argument missing: path");
        return nullptr;
    }
    
    std::string chmPath = NapiValueToString(env, args[0]);
    struct chmFile *h = chm_open(chmPath.c_str());
    if (h == nullptr) {
        // Return empty array if failed
        napi_value result;
        napi_create_array(env, &result);
        return result;
    }
    
    std::vector<std::string> filePaths;
    
    // Enumerate all files (CHM_ENUMERATE_FILES)
    chm_enumerate(h, CHM_ENUMERATE_FILES, EnumeratorCallback, &filePaths);
    
    chm_close(h);
    
    // Convert vector to JS Array
    napi_value jsArray;
    napi_create_array(env, &jsArray);
    
    for (size_t i = 0; i < filePaths.size(); i++) {
        napi_value jsString;
        napi_create_string_utf8(env, filePaths[i].c_str(), NAPI_AUTO_LENGTH, &jsString);
        napi_set_element(env, jsArray, i, jsString);
    }
    
    return jsArray;
}

static uint16_t read_uint16(const unsigned char* p) {
    return (uint16_t)(p[0] | (p[1] << 8));
}

// -------------------------------------------------------------------------
// 核心接口：从 #SYSTEM 文件获取 Default Topic
// 参数 1 (String): CHM 文件在沙箱中的绝对路径
// 返回值: String (Default Topic, e.g. "/intro.htm") 或者是空字符串
// -------------------------------------------------------------------------
static napi_value GetHomeFile(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};

    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1) {
        napi_throw_error(env, nullptr, "Argument missing: path");
        return nullptr;
    }

    std::string chmPath = NapiValueToString(env, args[0]);
    struct chmFile *h = chm_open(chmPath.c_str());
        
    napi_value result;
    napi_create_string_utf8(env, "", 0, &result); // Default return empty
    
    if (h == nullptr) {
        return result;
    }

    struct chmUnitInfo ui;
    // Try both /#SYSTEM and #SYSTEM just in case, but usually path resolution in chmlib expects / prefix or handles root
    // chmlib's chm_resolve_object expects paths starting with /
    if (chm_resolve_object(h, "/#SYSTEM", &ui) == CHM_RESOLVE_SUCCESS) {
        unsigned char *buf = (unsigned char *)malloc(ui.length);
        if (buf) {
            if (chm_retrieve_object(h, &ui, buf, 0, ui.length) > 0) {
               // Parse #SYSTEM
               // Header: Version (4 bytes)
               // Records: Code (2 bytes), Length (2 bytes), Data (Length bytes)
               
               if (ui.length >= 4) {
                  // Skip version (4 bytes)
                  size_t offset = 4;
                  while (offset + 4 <= ui.length) {
                       uint16_t code = read_uint16(buf + offset);
                       uint16_t len = read_uint16(buf + offset + 2);
                       offset += 4;
                       
                       if (offset + len > ui.length) break;
                       
                       // Code 2 is Default Topic
                       if (code == 2) {
                           // Data is null-terminated string, but let's be safe
                           std::string topic((char*)(buf + offset), len > 0 ? len - 1 : 0); // exclude null terminator if present
                           // Ensure it starts with /
                           if (!topic.empty() && topic[0] != '/') {
                               topic = "/" + topic;
                           }
                           napi_create_string_utf8(env, topic.c_str(), NAPI_AUTO_LENGTH, &result);
                           break;
                       }
                       
                       offset += len;
                  }
               }
            }
            free(buf);
        }
    }
    
    chm_close(h);
    return result;
}

// -------------------------------------------------------------------------
// 模块注册模板代码
// -------------------------------------------------------------------------
EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    // 定义暴露给 ArkTS 的方法
    napi_property_descriptor desc[] = {
        { "readContent", nullptr, ReadChmFileContent, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getFileList", nullptr, GetFileList, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getHomeFile", nullptr, GetHomeFile, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    
    // 挂载方法到 exports 对象上
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module _module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "chmlib", // 【重要】必须与 module.json5 或 import 时的名称一致
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&_module);
}