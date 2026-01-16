import fs from '@ohos.file.fs';
import router from '@ohos.router';
import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import picker from '@ohos.file.picker';

@Entry
@Component
struct Index {
  @State files: Array<string> = [];
  
  aboutToAppear() {
    this.handleExternalLaunch();
    this.copySampleFromRawFile(); // Try to load sample file
    this.refreshFileList();
  }

  onPageShow() {
    this.handleExternalLaunch();
    this.refreshFileList();
  }
  
  // Handle file opened from File Manager
  handleExternalLaunch() {
      const uri = AppStorage.get<string>('launchedFromUri');
      if (uri) {
          // Consume the event
          AppStorage.setOrCreate('launchedFromUri', '');
          this.importExernalFile(uri);
      }
  }

  async importExernalFile(uri: string) {
       const context = getContext(this) as common.UIAbilityContext;
       try {
            // Copy to filesDir
            const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
            // Use original name if possible, or timestamp
            // Note: getting name from URI might need tricky parsing or file stats. 
            // Simple generic name for now or try to parse
            let fileName = "imported_" + new Date().getTime() + ".chm"; 
            
            // Try to extract name?
            // "file://docs/storage/Users/currentUser/Documents/test.chm"
            const parts = uri.split('/');
            if (parts.length > 0) {
                const name = parts[parts.length - 1];
                if (name.endsWith('.chm') || name.endsWith('.CHM')) {
                    fileName = decodeURIComponent(name);
                }
            }

            const destPath = context.filesDir + "/" + fileName;
            
            // Prevent self-overwrite if somehow same path (unlikely given URI scheme differences)
            
            const buffer = new ArrayBuffer(4096);
            const destFile = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
            
            let len = 0;
            let pos = 0;
            while ((len = fs.readSync(file.fd, buffer, { offset: pos })) > 0) {
               fs.writeSync(destFile.fd, buffer, { length: len });
               pos += len;
            }
            
            fs.closeSync(file);
            fs.closeSync(destFile);
            
            console.info("Imported external file: " + destPath);
            this.refreshFileList();
            this.openReader(destPath);
       } catch (e) {
            console.error('External import failed', e);
       }
  }

  async copySampleFromRawFile() {
    // Modify 'test.chm' to your file name in rawfile
    const sampleFileName = 'test.chm'; 
    const context = getContext(this) as common.UIAbilityContext;
    const destPath = context.filesDir + '/' + sampleFileName;

    try {
      // Check if file already exists to avoid overwriting every time
      if (fs.accessSync(destPath)) {
         return;
      }

      // Check if exists in rawfile (by trying to get it)
      const resourceMgr = context.resourceManager;
      const data = await resourceMgr.getRawFileContent(sampleFileName);
      
      const file = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      fs.writeSync(file.fd, data.buffer);
      fs.closeSync(file);
      
      console.info('Sample file copied successfully');
      this.refreshFileList(); // Refresh list after copy
    } catch (e) {
      // It works silently if file not found in rawfile
      console.info('No sample file found or copy failed:', e.message);
    }
  }

  async refreshFileList() {
    const context = getContext(this) as common.UIAbilityContext;
    const filesDir = context.filesDir;
    try {
       // Ensure directory exists
       if (!fs.accessSync(filesDir)) {
          fs.mkdirSync(filesDir);
       }
       
       const filenames = fs.listFileSync(filesDir);
       let allFiles = filenames
          .filter(f => f.toLowerCase().endsWith('.chm'))
          .map(f => filesDir + '/' + f);

       // Sort by history (recently accessed first)
       try {
           const pref = await preferences.getPreferences(context, 'chm_history');
           const history = await pref.get('recent_files', []) as string[];
           
           allFiles.sort((a, b) => {
               const idxA = history.indexOf(a);
               const idxB = history.indexOf(b);
               
               // Both in history: maintain relative order from history
               if (idxA !== -1 && idxB !== -1) {
                   return idxA - idxB;
               }
               // Only a in history -> a comes first
               if (idxA !== -1) {
                   return -1;
               }
               // Only b in history -> b comes first
               if (idxB !== -1) {
                   return 1;
               }
               // Neither in history -> Alphabetical sort
               return a.localeCompare(b);
           });
       } catch (e) {
           console.error("Failed to sort by history", e);
       }

       this.files = allFiles;
    } catch (e) {
       console.error("Failed to list files", e);
    }
  }

  // loadHistory removed - not needed for display anymore, sorting is done in refreshFileList
  
  async addToHistory(path: string) {
     const context = getContext(this) as common.UIAbilityContext;
     try {
       const pref = await preferences.getPreferences(context, 'chm_history');
       let history = await pref.get('recent_files', []) as string[];
       // Remove if exists to move to top
       history = history.filter(p => p !== path);
       history.unshift(path);
       // access limit
       if (history.length > 20) {
          history = history.slice(0, 20);
       }
       await pref.put('recent_files', history);
       await pref.flush();
     } catch (e) {
       console.error("Failed to save history", e);
     }
  }

  openReader(file: string) {
     this.addToHistory(file);
     router.pushUrl({
        url: 'pages/ReaderPage',
        params: {
           path: file
        }
     });
  }
  
  async pickFile() {
      try {
        const documentViewPicker = new picker.DocumentViewPicker();
        const documentSelectOptions = new picker.DocumentSelectOptions();
        documentSelectOptions.maxSelectNumber = 1;
        documentSelectOptions.fileSuffixFilters = ['.chm']; 
        
        const uris = await documentViewPicker.select(documentSelectOptions);
        if (uris && uris.length > 0) {
            const uri = uris[0];
            const context = getContext(this) as common.UIAbilityContext;
            
            // Copy to filesDir
            const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
            // Use original name if possible, or timestamp
            const fileName = "imported_" + new Date().getTime() + ".chm"; 
            const destPath = context.filesDir + "/" + fileName;
            
            // Copy using buffer reading/writing to be safe across schemes
            const buffer = new ArrayBuffer(4096);
            const destFile = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
            
            let len = 0;
            let pos = 0;
            while ((len = fs.readSync(file.fd, buffer, { offset: pos })) > 0) {
               fs.writeSync(destFile.fd, buffer, { length: len });
               // readSync with offset doesn't advance file ptr automatically if we specify offset?
               // Wait, fs.readSync(fd, buffer, options). If offset is used, it reads from that position.
               // If we want sequential, we should NOT pass offset, or update it.
               // Actually handling streams is better.
               // Attempt copyFileSync first
               // fs.copyFileSync(file.fd, destFile.fd); // Not supported standardly this way maybe?
               pos += len;
            }
            // Actually, simpler:
            // fs.copyFileSync(file.fd, destPath); // Spec says src can be number? 
            // If manual copy is needed:
            
            fs.closeSync(file);
            fs.closeSync(destFile);

            this.refreshFileList();
            this.openReader(destPath);
        }
      } catch (e) {
         console.error('Picker failed', e);
      }
  }

  build() {
    Column() {
      Row() {
         Text("CHM 阅读器")
           .fontSize(20)
           .fontWeight(FontWeight.Bold)
           .margin({ left: 20 })
         
         Blank()
         
         Button("关于")
           .type(ButtonType.Normal)
           .backgroundColor(Color.Transparent)
           .fontColor(Color.Blue)
           .onClick(() => {
              router.pushUrl({ url: 'pages/AboutPage' });
           })
           .margin({ right: 20 })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(Color.White)
      
      Column() {
        if (this.files.length === 0) {
          Column() {
            Image($r('app.media.startIcon'))
               .width(60)
               .height(60)
               .opacity(0.5)
               .margin({ bottom: 10 })
            Text("暂无文件，请导入")
               .fontSize(16)
               .fontColor(Color.Gray)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
             List() {
                ForEach(this.files, (file: string) => {
                   ListItem() {
                      Row() {
                         // Image($r('app.media.startIcon')).width(30).height(30).margin({right: 10})
                         Text(file.split('/').pop()).fontSize(16)
                           .layoutWeight(1)
                           .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .width('100%')
                      .padding(15)
                      .backgroundColor(Color.White)
                      .borderRadius(10)
                      .margin({bottom: 5})
                      .onClick(() => this.openReader(file))
                   }
                }, (item: string) => item)
             }
             .width('100%')
             .layoutWeight(1)
             .padding(10)
        }
             
        Button("导入文件")
           .width('80%')
           .margin(20)
           .onClick(() => this.pickFile())
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#f0f2f5')
    }
    .width('100%')
    .height('100%')
  }
}
