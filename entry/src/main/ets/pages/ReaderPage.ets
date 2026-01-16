
import router from '@ohos.router';
import { chmlib } from 'chmlib';
import { util } from '@kit.ArkTS';
import web_webview from '@ohos.web.webview';
import { BusinessError } from '@kit.BasicServicesKit';

interface TocItem {
  name: string;
  path: string;
  level: number;
}

@Entry
@Component
struct ReaderPage {
  @State chmPath: string = '';
  @State currentPath: string = '/index.html'; // Default entry
  @State isTocVisible: boolean = false;
  @State tocList: TocItem[] = [];
  
  controller: web_webview.WebviewController = new web_webview.WebviewController();
  
  aboutToAppear() {
    const params = router.getParams() as Record<string, string>;
    if (params && params['path']) {
      this.chmPath = params['path'];
      
      // 动态获取主页
      const home = chmlib.getHomeFile(this.chmPath);
      if (home && home.length > 0) {
        this.currentPath = home;
      }

      this.loadToc();
    }
  }

  loadToc() {
    try {
      // 1. Get file list to find .hhc
      const files = chmlib.getFileList(this.chmPath);
      const hhcFile = files.find(f => f.toLowerCase().endsWith('.hhc'));
      
      if (hhcFile) {
        // 2. Read .hhc content
        const buffer = chmlib.readContent(this.chmPath, hhcFile);
        if (buffer) {
           let content = "";
           const uint8Array = new Uint8Array(buffer);

           // Encoding detection strategy
           try {
              // 1. Try UTF-8 with fatal=true to strictly validate
              let decoder = util.TextDecoder.create("utf-8", { fatal: true });
              content = decoder.decodeWithStream(uint8Array);
           } catch (e) {
              console.info("TOC not UTF-8, trying GBK");
              try {
                  // 2. Fallback to GBK (Common for Chinese CHMs)
                  let decoder = util.TextDecoder.create("gbk", { ignoreBOM: true });
                  content = decoder.decodeWithStream(uint8Array);
              } catch (e2) {
                  // 3. Final Fallback (Windows-1252 / ISO-8859-1)
                  console.info("GBK failed, using Windows-1252");
                  let decoder = util.TextDecoder.create("windows-1252", { ignoreBOM: true });
                  content = decoder.decodeWithStream(uint8Array);
              }
           }
           
           // 3. Simple Regex Parse
           // This is a naive parser. 
           // We look for <param name="Name" value="..."> and <param name="Local" value="...">
           // Indentation/Nesting is approximated by <UL> tags if we want tree, 
           // or just flat list for simplicity first.
           
           const items: TocItem[] = [];
           const lines = content.split('\n');
           
           let currentName = "";
           let currentPath = "";
           
           // Simple state machine
           // 0: searching for <OBJECT
           // 1: inside <OBJECT, searching for params
           
           const regexName = /<param\s+name="Name"\s+value="([^"]+)"/i;
           const regexLocal = /<param\s+name="Local"\s+value="([^"]+)"/i;
           
           for (const line of lines) {
              const nameMatch = line.match(regexName);
              if (nameMatch) currentName = nameMatch[1];
              
              const localMatch = line.match(regexLocal);
              if (localMatch) currentPath = localMatch[1];
              
              if (line.includes("</OBJECT>") || line.includes("</object>")) {
                  if (currentName && currentPath) {
                      // Normalize path to start with /
                      let cleanPath = currentPath.replaceAll('\\', '/');
                      if (!cleanPath.startsWith('/')) cleanPath = '/' + cleanPath;
                      
                      items.push({ name: currentName, path: cleanPath, level: 0 });
                  }
                  currentName = "";
                  currentPath = "";
              }
           }
           this.tocList = items;
        }
      }
    } catch (e) {
      console.error("Failed to load TOC", e);
    }
  }

  build() {
    SideBarContainer(SideBarContainerType.Overlay) {
       // SideBar Content (TOC)
       Column() {
         Text("目录")
           .fontSize(20)
           .fontWeight(FontWeight.Bold)
           .margin(20)
         
         if (this.tocList.length === 0) {
            Text("未找到目录或解析失败")
              .fontColor(Color.Gray)
              .margin(20)
         } else {
            List() {
              ForEach(this.tocList, (item: TocItem) => {
                 ListItem() {
                   Text(item.name)
                     .fontSize(16)
                     .fontColor(Color.Black)
                     .padding(10)
                     .width('100%')
                     .onClick(() => {
                        this.loadPage(item.path);
                        this.isTocVisible = false; // Close sidebar on mobile/overlay mode
                     })
                 }
              })
            }
            .layoutWeight(1)
            .width('100%')
            .divider({ strokeWidth: 1, color: '#f0f0f0' })
         }
       }
       .backgroundColor(Color.White)
       .width('100%')
       .height('100%')

       // Main Content
       Column() {
        // Navigation Bar
        Row() {
          Button('目录')
            .onClick(() => {
               this.isTocVisible = !this.isTocVisible;
            })
            .margin({ right: 10 })

          Button('返回')
            .onClick(() => {
               router.back();
            })
            .margin({ right: 10 })

          Text(this.chmPath.split('/').pop())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#f1f3f5')
  
        // Web View
        Web({ src: '', controller: this.controller })
          .width('100%')
          .layoutWeight(1)
          .onControllerAttached(() => {
               this.loadPage(this.currentPath);
          })
          .onPageBegin((event) => {
            if (event) {
              console.info('Current URL: ' + event.url);
            }
          })
          .onInterceptRequest((event) => {
            if (event && event.request && event.request.getRequestUrl()) {
               const url = event.request.getRequestUrl();
               // Custom scheme handling: using http://local/ inside webview to map to CHM content
               if (url.startsWith('https://chm.local/')) {
                  let innerPath = url.replace('https://chm.local', '');
  
                  // Clean up the path: remove fragment (#) and query (?) which are not part of the filename
                  // specific for CHM file lookup
                  innerPath = innerPath.split('#')[0].split('?')[0];
  
                  // Decode URL path
                  const decodedPath = decodeURIComponent(innerPath);
                  
                  const buffer = chmlib.readContent(this.chmPath, decodedPath);
                  if (buffer) {
                     const response = new WebResourceResponse();
                     // Prepare response
                     response.setResponseData(buffer);
                     response.setResponseCode(200);
                     response.setReasonMessage('OK');
                     
                     // Guess mime type
                     if (decodedPath.endsWith('.html') || decodedPath.endsWith('.htm')) {
                        response.setResponseMimeType('text/html');
                        
                        let encoding = 'utf-8';
                        try {
                          // Try to decode as UTF-8 with fatal=true to detect if it's valid UTF-8
                          let textDecoder = util.TextDecoder.create("utf-8", { fatal: true });
                          textDecoder.decodeWithStream(new Uint8Array(buffer));
                        } catch (e) {
                          // If failed, assume GBK
                          encoding = 'gbk';
                        }
                        response.setResponseEncoding(encoding);
                     } else if (decodedPath.endsWith('.png')) {
                        response.setResponseMimeType('image/png');
                     } else if (decodedPath.endsWith('.jpg') || decodedPath.endsWith('.jpeg')) {
                        response.setResponseMimeType('image/jpeg');
                     } else if (decodedPath.endsWith('.css')) {
                        response.setResponseMimeType('text/css');
                     } else if (decodedPath.endsWith('.js')) {
                        response.setResponseMimeType('application/javascript');
                     } else {
                        response.setResponseMimeType('application/octet-stream');
                     }
                     return response;
                  }
               }
            }
            return null;
          })
      }
      .width('100%')
      .height('100%')
    }
    .showSideBar(this.isTocVisible)
    .showControlButton(false)
    .onChange((value: boolean) => {
       this.isTocVisible = value;
    })
    .sideBarWidth(250)
    .minSideBarWidth(200)
    .maxSideBarWidth(300)
    .width('100%')
    .height('100%')
  }

  loadPage(innerPath: string) {
      // We use a fake domain to route requests through onInterceptRequest
      // This allows relative links in HTML to resolve correctly against this base
      const url = `https://chm.local${innerPath}`;
      this.controller.loadUrl(url);
  }
}
