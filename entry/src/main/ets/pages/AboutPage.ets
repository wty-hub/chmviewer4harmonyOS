
import router from '@ohos.router';

@Entry
@Component
struct AboutPage {
  @State appVersion: string = '1.0.0';
  @State appName: string = 'CHM Viewer';

  build() {
    Column() {
      // Header
      Row() {
         Button("返回")
           .onClick(() => router.back())
           .margin({ left: 15, top: 15 })
      }.width('100%').justifyContent(FlexAlign.Start)

      // Content
      Column() {
        Image($r('app.media.startIcon'))
          .width(80)
          .height(80)
          .margin({ top: 50, bottom: 20 })
          
        Text(this.appName)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 10 })
          
        Text(`Version: ${this.appVersion}`)
          .fontSize(16)
          .fontColor(Color.Gray)
          .margin({ bottom: 30 })
          
        Text('鸿蒙系统的简单CHM阅读器 王天一制作')
          .fontSize(16)
          .textAlign(TextAlign.Center)
          .padding({ left: 20, right: 20 })
          .fontColor('#333333')
          
        Blank()
        
        Text('Copyright © 2026')
          .fontSize(12)
          .fontColor(Color.Gray)
          .margin({ bottom: 20 })
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
    .onClick(() => {
        // Click anywhere to back? No, maybe just back button hardware
    })
  }

  onBackPress() {
      router.back();
      return true;
  }
}
