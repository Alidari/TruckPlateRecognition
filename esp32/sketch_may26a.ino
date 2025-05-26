#include <WiFi.h>
#include <WebServer.h>

// Wi-Fi Bilgileri
const char* ssid = "***********************";
const char* password = "****************";

WebServer server(80);
const int ledPin = 2;  // GPIO 2

// LED açık kalma süresi (milisaniye cinsinden)
unsigned long ledDuration = 2000;  // 2 saniye
unsigned long ledOnTime = 0;
bool ledActive = false;

void handlePostData() {
  if (server.hasArg("plain")) {
    String data = server.arg("plain");
    Serial.println("Gelen veri: " + data);

    if (data == "ON") {
      digitalWrite(ledPin, HIGH);
      ledOnTime = millis();  // şu anki zamanı kaydet
      ledActive = true;
      Serial.println("LED YAKILDI (süreli)");
    } else if (data == "OFF") {
      digitalWrite(ledPin, LOW);
      ledActive = false;
      Serial.println("LED SÖNDÜRÜLDÜ (manuel)");
    }

    server.send(200, "text/plain", "Veri alındı!");
  } else {
    server.send(400, "text/plain", "Veri yok!");
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(ledPin, OUTPUT);
  digitalWrite(ledPin, LOW);

  WiFi.begin(ssid, password);
  Serial.print("Wi-Fi'ye bağlanıyor");

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("");
  Serial.println("Wi-Fi bağlantısı başarılı!");
  Serial.println(WiFi.localIP());

  server.on("/data", HTTP_POST, handlePostData);
  server.begin();
  Serial.println("Server başlatıldı!");
}

void loop() {
  server.handleClient();

  // Eğer LED aktifse ve süre dolmuşsa söndür
  if (ledActive && millis() - ledOnTime >= ledDuration) {
    digitalWrite(ledPin, LOW);
    ledActive = false;
    Serial.println("LED otomatik olarak kapatıldı");
  }
}
