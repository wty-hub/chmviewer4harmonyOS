/**
 * 从 CHM 文件中读取指定文件的内容
 * @param chmPath CHM 文件在设备上的绝对路径 (沙箱路径)
 * @param innerPath CHM 内部的文件路径 (例如 "/index.html" 或 "/images/logo.png")
 * @returns 文件的二进制内容 (ArrayBuffer)，如果读取失败返回 undefined
 */
export const readContent: (chmPath: string, innerPath: string) => ArrayBuffer | undefined;

/**
 * 获取 CHM 文件内所有文件的路径列表
 * @param chmPath CHM 文件路径
 * @returns 文件路径字符串数组
 */
export const getFileList: (chmPath: string) => string[];

/**
 * 获取 CHM 文件的默认首页
 * @param chmPath CHM 文件路径
 * @returns 首页路径 (例如 "/index.html")，如果未找到则返回空字符串
 */
export const getHomeFile: (chmPath: string) => string;
