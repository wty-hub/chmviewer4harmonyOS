import chmlib from 'libchmlib.so';
import { util } from '@kit.ArkTS'; // 用于解码文本
import image from '@ohos.multimedia.image'; // 用于处理图片

@Entry
@Component
struct ChmReader {
  @State htmlContent: string = "等待读取...";
  @State imagePixelMap: image.PixelMap | undefined = undefined;

  testReadChm() {
    // 假设 chm 文件已经在沙箱路径: /data/storage/.../files/help.chm
    let chmPath = getContext(this).filesDir + "/help.chm";

    // 1. 读取 HTML 文本
    let buffer = chmlib.readContent(chmPath, "/index.html");
    if (buffer) {
      // ArrayBuffer -> String (假设是 UTF-8 编码，CHM 有时是 GBK，需要注意)
      let textDecoder = util.TextDecoder.create("utf-8"); // 如果是中文旧文档可能是 "gbk"
      this.htmlContent = textDecoder.decodeWithStream(new Uint8Array(buffer));
    } else {
      console.error("读取 HTML 失败");
    }

    // 2. 读取图片
    let imgBuffer = chmlib.readContent(chmPath, "/images/icon.png");
    if (imgBuffer) {
      // imgBuffer 可以直接传给 ImageSource 创建 PixelMap
      let imageSource = image.createImageSource(imgBuffer);
      imageSource.createPixelMap().then((pixelMap) => {
        this.imagePixelMap = pixelMap;
      })
    }
  }

  build() {
    Column() {
      Button("读取 CHM").onClick(() => this.testReadChm())
      Text(this.htmlContent).margin(10)
      if (this.imagePixelMap) {
        Image(this.imagePixelMap).width(100).height(100)
      }
    }
  }
}