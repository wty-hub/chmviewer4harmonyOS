import router from '@ohos.router';
import { chmlib } from 'chmlib';
import { util } from '@kit.ArkTS';
import web_webview from '@ohos.web.webview';
import { BusinessError } from '@kit.BasicServicesKit';
import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';

interface TocItem {
  id: number;
  name: string;
  path: string;
  level: number;
  isExpanded: boolean;
  hasChildren: boolean;
}

@Entry
@Component
struct ReaderPage {
  @State chmPath: string = '';
  @State currentPath: string = '/index.html'; // Default entry
  @State isTocVisible: boolean = false;
  @State tocList: TocItem[] = []; // visible list
  private allTocItems: TocItem[] = []; // full list data
  controller: web_webview.WebviewController = new web_webview.WebviewController();
  isControllerReady: boolean = false;

  aboutToAppear() {
    const params = router.getParams() as Record<string, string>;
    if (params && params['path']) {
      this.chmPath = params['path'];
      this.initPageContent();
    }
  }

  async initPageContent() {
    // 1. Try restore from preferences
    let path = await this.restoreLastPosition();

    // 2. If no saved position, try CHM home
    if (!path) {
      const home = chmlib.getHomeFile(this.chmPath);
      if (home && home.length > 0) {
        path = home;
      }
    }

    // 3. Fallback
    if (path) {
      this.currentPath = path;
    }

    if (this.isControllerReady) {
      this.loadPage(this.currentPath);
    }

    this.loadToc();
  }

  async restoreLastPosition(): Promise<string> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const prefs = await preferences.getPreferences(context, 'chm_reader_store');
      const key = this.chmPath.replace(/[\\/]/g, '_');
      const saved = await prefs.get(key, '');
      console.info('Restored position: ' + saved);
      return saved as string;
    } catch (e) {
      console.error('Failed to restore position', e);
      return '';
    }
  }

  async saveLastPosition(path: string) {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const prefs = await preferences.getPreferences(context, 'chm_reader_store');
      const key = this.chmPath.replace(/[\\/]/g, '_');
      await prefs.put(key, path);
      await prefs.flush();
      // console.info('Saved position: ' + path);
    } catch (e) {
      console.error('Failed to save position', e);
    }
  }

  async loadToc() {
    try {
      console.info("ReaderPage.loadToc: chmPath=" + this.chmPath);
      let content = "";
      let tocPath = "";

      // Strategy 1: Get Toc file from #SYSTEM (Standard way)
      try {
        const sysToc = chmlib.getTocFile(this.chmPath);
        console.info("getTocFile returned: '" + sysToc + "' (length: " + sysToc.length + ")");
        if (sysToc && sysToc.length > 0) {
          console.info("Found TOC in #SYSTEM: " + sysToc);
          tocPath = sysToc;
        } else {
          console.warn("getTocFile returned empty or null");
        }
      } catch (err) {
        console.warn("Failed to read #SYSTEM TOC: " + err);
      }

      // Strategy 2: Fallback - Scan for any .hhc file
      if (!tocPath) {
        console.warn("No TOC in #SYSTEM, scanning file list...");
        const files = chmlib.getFileList(this.chmPath);
        console.info(`FileList: Total ${files.length} files found.`);
        if (files.length > 0) {
             console.info(`First file: ${files[0]}`);
        }
        
        // Debug: print any potential matches manually
        files.forEach(f => {
            if (f.toLowerCase().includes('.hhc') || f.toLowerCase().includes('toc')) {
                console.info(`Potential TOC candidate: ${f}`);
            }
        });

        const hhcFile = files.find(f => f.toLowerCase().endsWith('.hhc'));
        if (hhcFile) {
          tocPath = hhcFile;
          console.info("Found fallback TOC file: " + tocPath);
        }
      }

      if (tocPath) {
        // Read .hhc content
        const buffer = chmlib.readContent(this.chmPath, tocPath);
        if (buffer) {
          const uint8Array = new Uint8Array(buffer);

          // Encoding detection strategy
          try {
            // 1. Try UTF-8 first
            let decoder = util.TextDecoder.create("utf-8", { fatal: true });
            content = decoder.decodeWithStream(uint8Array);
          } catch (e) {
            console.info("TOC not UTF-8, trying GBK");
            try {
              // 2. Fallback to GBK
              let decoder = util.TextDecoder.create("gbk", { ignoreBOM: true });
              content = decoder.decodeWithStream(uint8Array);
            } catch (e2) {
              // 3. Final fallback
              console.info("GBK failed, using Windows-1252");
              let decoder = util.TextDecoder.create("windows-1252", { ignoreBOM: true });
              content = decoder.decodeWithStream(uint8Array);
            }
          }

          // Parse CHM TOC according to standard format
          // CHM .hhc files follow HTML Help Workshop format:
          // <UL>
          //   <LI><OBJECT type="text/sitemap">
          //         <param name="Name" value="Chapter Title">
          //         <param name="Local" value="file.html">
          //       </OBJECT>
          //     <UL>  <!-- Nested items -->
          //       <LI>...
          //     </UL>
          //   </LI>
          // </UL>
          this.allTocItems = this.parseHhcContent(content);
          this.refreshVisibleToc();
          console.info(`TOC parsed: found ${this.allTocItems.length} items`);
          return;
        }
      }

      console.warn("No valid TOC found via #SYSTEM or scan.");
      // If we reach here, we could try to synthesize a TOC from file list (very basic)
      if (this.allTocItems.length === 0) {
        const files = chmlib.getFileList(this.chmPath);
        const htmlFiles = files.filter(f => f.toLowerCase().endsWith('.htm') || f.toLowerCase().endsWith('.html'));
        this.allTocItems = htmlFiles.slice(0, 50).map((f, index): TocItem => {
          return { id: index, name: f.split('/').pop() || f, path: f, level: 0, isExpanded: false, hasChildren: false };
        });
        this.refreshVisibleToc();
        console.info("Synthesized basic TOC from file list");
      }

    } catch (e) {
      console.error("Failed to load TOC", e);
    }
  }

  // 按CHM标准解析.hhc文件内容 - rewritten linear parser
  parseHhcContent(content: string): TocItem[] {
    const items: TocItem[] = [];
    
    // Remove comments and normalize whitespace
    content = content.replace(/<!--[\s\S]*?-->/g, '');
    
    // Extract the body content
    const bodyMatch = content.match(/<body[^>]*>([\s\S]*)<\/body>/i);
    if (bodyMatch) {
      content = bodyMatch[1];
    }
    
    let currentLevel = 0;
    // Regex matches: <UL...> OR </UL> OR <OBJECT...>...</OBJECT>
    const tokenRegex = /(<ul\b[^>]*>)|(<\/ul>)|(<object\b[^>]*>[\s\S]*?<\/object>)/gi;
    
    let match: RegExpExecArray | null;
    let idCounter = 0;

    while ((match = tokenRegex.exec(content)) !== null) {
      const fullMatch = match[0];
      
      if (match[1]) { // <UL>
        currentLevel++;
      } else if (match[2]) { // </UL>
        currentLevel--;
      } else if (match[3]) { // <OBJECT>
        const objectContent = fullMatch;
        
        // Extract parameters
        const getParam = (paramName: string): string => {
          const patterns = [
            new RegExp(`<param\\s+name=["']?${paramName}["']?\\s+value=["']([^"']*)["']`, 'i'),
            new RegExp(`<param\\s+value=["']([^"']*)["']\\s+name=["']?${paramName}["']?`, 'i'),
            new RegExp(`<param\\s+name=${paramName}\\s+value=([^\\s>"']*)`, 'i')
          ];
          
          for (let pattern of patterns) {
            const pMatch = objectContent.match(pattern);
            if (pMatch && pMatch[1]) {
              return pMatch[1].trim();
            }
          }
          return "";
        };
        
        const name = getParam("Name");
        const local = getParam("Local");
        
        if (name) {
          let cleanPath = "";
          if (local) {
            cleanPath = local.replace(/\\/g, '/');
            cleanPath = cleanPath.split('?')[0].split('#')[0];
            if (!cleanPath.startsWith('/')) {
              cleanPath = '/' + cleanPath;
            }
          }
          
          items.push({ 
            id: idCounter++,
            name: name, 
            path: cleanPath, 
            level: Math.max(0, currentLevel - 1), // Adjust based on assumption that root UL starts at level 1
            isExpanded: false,
            hasChildren: false
          });
        }
      }
    }
    
    // Normalize levels if needed (e.g. if everything started at level 1)
    if (items.length > 0) {
      const minLevel = Math.min(...items.map(i => i.level));
      if (minLevel > 0) {
        items.forEach(i => i.level -= minLevel);
      }
      
      // Calculate hasChildren
      for (let i = 0; i < items.length - 1; i++) {
        if (items[i + 1].level > items[i].level) {
           items[i].hasChildren = true;
        }
      }
      // Last item never has children in this linear structure
    }
    
    return items;
  }
  
  refreshVisibleToc() {
    const result: TocItem[] = [];
    let hideLevel = -1;
    
    for (const item of this.allTocItems) {
      if (hideLevel !== -1) {
        if (item.level > hideLevel) {
           continue; // Skip hidden children
        } else {
           hideLevel = -1; // Reset when back to same or higher level
        }
      }
      
      result.push(item);
      
      // If this item is collapsed and has children, start hiding deeper levels
      if (item.hasChildren && !item.isExpanded) {
        hideLevel = item.level;
      }
    }
    this.tocList = result;
  }
  
  toggleExpanded(item: TocItem) {
    const target = this.allTocItems.find(i => i.id === item.id);
    if (target) {
      target.isExpanded = !target.isExpanded;
      this.refreshVisibleToc();
    }
  }

  build() {
    SideBarContainer(SideBarContainerType.Embed) {
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
                Row() {
                  // 根据层级添加缩进
                  Text("")
                    .width(item.level * 20)
                  
                  // 层级指示器 / 展开按钮
                  if (item.hasChildren) {
                    // 使用不易被渲染为Emoji的字符，并强制背景透明
                    Text(item.isExpanded ? "▾" : "▸")
                      .fontSize(26)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.Black)
                      .backgroundColor(Color.Transparent)
                      .width(40)
                      .textAlign(TextAlign.Center)
                      .onClick((event: ClickEvent) => {
                        this.toggleExpanded(item);
                      })
                  } else {
                    Text("• ")
                      .fontSize(14)
                      .fontColor(Color.Gray)
                      .width(40)
                      .textAlign(TextAlign.Center)
                  }
                  
                  // 项目名称
                  Text(item.name)
                    .fontSize(item.level === 0 ? 16 : 15)
                    .fontColor(item.level === 0 ? Color.Black : '#333333')
                    .fontWeight(item.level === 0 ? FontWeight.Medium : FontWeight.Normal)
                    .layoutWeight(1)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .onClick(() => {
                  // 只有有路径的项目才能点击
                  if (item.path && item.path.length > 0) {
                    this.loadPage(item.path);
                    this.isTocVisible = false; // Close sidebar on mobile/overlay mode
                  }
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
            this.isControllerReady = true;
            if (this.currentPath) {
              this.loadPage(this.currentPath);
            }
          })
          .onPageBegin((event) => {
            if (event) {
              console.info('Current URL: ' + event.url);
              // Save progress
              if (event.url.startsWith('https://chm.local')) {
                const newPath = event.url.substring('https://chm.local'.length);
                this.currentPath = newPath;
                this.saveLastPosition(newPath);
              }
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
