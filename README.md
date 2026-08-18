# LineMessenger_Wine
LineMessenger_Wine

本專案是為了解決 64bit LineInsta.exe 需要簽署認證的痛點進行一鍵簽署的工具，
只需要貼上 Bottles 容器的 Windows 資料夾路徑自行簽署後就可以正常執行 64bit Line Windows 程式。

執行前請先授權 sh 檔案可執行 （也可使用圖形操作)
chmod +x fix_line_wine.sh
之後直接執行
./fix_line_wine.sh

會跳出圖形界面要你選取 Windows 資料夾
(我建議關掉直接採用貼上路徑即可)

安裝 LineInsta.exe 建議先安裝 cjkfonts 的相依套件
部份顯卡不支援圖形繪出（閃退）
設定酒瓶把 DXVK 停用可解。
