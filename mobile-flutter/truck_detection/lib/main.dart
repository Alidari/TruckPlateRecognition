import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Güvenlik Kapısı Sistemi',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      home: SecurityGateScreen(),
    );
  }
}

class SecurityGateScreen extends StatefulWidget {
  @override
  _SecurityGateScreenState createState() => _SecurityGateScreenState();
}

class _SecurityGateScreenState extends State<SecurityGateScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _videoFile;
  VideoPlayerController? _videoController;
  bool _isLoading = false;
  bool _isAnalyzing = false;
  List<Map<String, dynamic>> _detectionResults = [];
  String _serverUrl = 'http://192.168.208.99:5000';
  String _gateUrl = 'http://192.168.208.116/data';

  // Güvenlik kapısı durumları
  String _gateStatus = 'KAPALI';
  String _securityMessage = 'Sistem Bekleme Modunda';
  String _plateNumber = '';
  bool _isGateOpen = false;
  bool _isTruckDetected = false;
  bool _isPlateVerified = false;
  String _currentPhase = 'waiting'; // waiting, detecting, verifying, approved, denied

  // Real-time analiz değişkenleri
  Map<String, dynamic>? _latestResult;
  int _processedFrames = 0;
  int _totalFrames = 0;
  double _analysisProgress = 0.0;

  // Kayıtlı plakalar
  List<String> _registeredPlates = [];

  @override
  void initState() {
    super.initState();
    _loadRegisteredPlates();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _pickVideoFromGallery() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final XFile? pickedFile = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: Duration(minutes: 10),
      );

      if (pickedFile != null) {
        setState(() {
          _videoFile = File(pickedFile.path);
          _resetSecuritySystem();
        });
        await _initializeVideoPlayer();
      }
    } catch (e) {
      _showErrorSnackBar('Video seçilirken hata oluştu: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickVideoFromCamera() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final XFile? pickedFile = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: Duration(minutes: 5),
        preferredCameraDevice: CameraDevice.rear,
      );

      if (pickedFile != null) {
        setState(() {
          _videoFile = File(pickedFile.path);
          _resetSecuritySystem();
        });
        await _initializeVideoPlayer();
      }
    } catch (e) {
      _showErrorSnackBar('Video çekilirken hata oluştu: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _resetSecuritySystem() {
    _detectionResults.clear();
    _latestResult = null;
    _processedFrames = 0;
    _totalFrames = 0;
    _analysisProgress = 0.0;
    _gateStatus = 'KAPALI';
    _securityMessage = 'Sistem Hazır - Güvenlik Taraması Bekleniyor';
    _plateNumber = '';
    _isGateOpen = false;
    _isTruckDetected = false;
    _isPlateVerified = false;
    _currentPhase = 'waiting';
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ),
    );
  }

  Future<void> _initializeVideoPlayer() async {
    if (_videoFile != null) {
      try {
        _videoController?.dispose();
        _videoController = VideoPlayerController.file(_videoFile!);
        await _videoController!.initialize();
        setState(() {});
      } catch (e) {
        _showErrorSnackBar('Video oynatıcı başlatılırken hata oluştu: $e');
      }
    }
  }

  void _playPauseVideo() {
    if (_videoController != null) {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
      setState(() {});
    }
  }

  Future<bool> _checkServerHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$_serverUrl/health'))
          .timeout(Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<void> _startSecurityScan() async {
    if (_videoController == null) return;

    bool serverOk = await _checkServerHealth();
    if (!serverOk) {
      _showErrorSnackBar('Sunucu bağlantısı kurulamadı!');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _currentPhase = 'detecting';
      _securityMessage = 'GÜVENLİK TARAMASI BAŞLATILIYOR...';
      _gateStatus = 'TARAMA AKTIF';
      _resetSecuritySystem();
      _isAnalyzing = true;
    });

    try {
      final duration = _videoController!.value.duration;
      const frameInterval = Duration(milliseconds: 500);
      _totalFrames = (duration.inMilliseconds / frameInterval.inMilliseconds).ceil();

      for (Duration currentTime = Duration.zero;
      currentTime < duration && _isAnalyzing;
      currentTime += frameInterval) {

        await _videoController!.seekTo(currentTime);
        await Future.delayed(Duration(milliseconds: 100));

        final result = await _captureAndAnalyzeFrame(currentTime);

        if (result == null) {
          setState(() {
            _securityMessage = 'BAĞLANTI HATASI - Sistem Durduruldu';
            _currentPhase = 'error';
          });
          break;
        }

        await _processSecurityResult(result, currentTime);

        // Kamyon tespit edildi ve plaka doğrulandıysa taramayı durdur
        if (_isPlateVerified && _isGateOpen) {
          await Future.delayed(Duration(seconds: 3)); // Biraz bekle
          break;
        }
      }

    } catch (e) {
      setState(() {
        _securityMessage = 'SISTEM HATASI: $e';
        _currentPhase = 'error';
      });
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  Future<void> _processSecurityResult(Map<String, dynamic> result, Duration timestamp) async {
    setState(() {
      _detectionResults.add(result);
      _latestResult = result;
      _processedFrames++;
      _analysisProgress = _processedFrames / _totalFrames;
    });

    if (result['status'] == 'truck') {
      if (!_isTruckDetected) {
        // İlk kamyon tespiti
        setState(() {
          _isTruckDetected = true;
          _currentPhase = 'verifying';
          _securityMessage = 'KAMYON TESPİT EDİLDİ - Plaka Doğrulanıyor...';
        });
        await Future.delayed(Duration(milliseconds: 800));
      }

      // Plaka kontrol et
      if (result['plate'] != null && result['plate'].isNotEmpty) {
        final detectedPlate = result['plate'].toString().toUpperCase();
        setState(() {
          _plateNumber = detectedPlate;
        });

        // Plaka kayıtlı mı kontrol et
        if (_isPlateRegistered(detectedPlate)) {
          setState(() {
            _isPlateVerified = true;
            _currentPhase = 'approved';
            _securityMessage = 'PLAKA DOĞRULANDI - Kapı Açılıyor...';
            _gateStatus = 'AÇIK';
            _isGateOpen = true;
          });

          // Kapıyı aç
          await _sendGateCommand('ON');

          setState(() {
            _securityMessage = 'ERİŞİM İZNİ VERİLDİ - Kapı Açık';
          });
        } else {
          setState(() {
            _currentPhase = 'denied';
            _securityMessage = 'UYARI: YETKİSİZ PLAKA - ERİŞİM REDDEDİLDİ!';
            _gateStatus = 'KAPALI - YETKİSİZ PLAKA';
          });
        }
      } else {
        setState(() {
          _securityMessage = 'PLAKA OKUNAMIYOR - Doğrulama Devam Ediyor...';
        });
      }

    } else if (result['status'] == 'other-vehicle') {
      setState(() {
        _currentPhase = 'denied';
        _securityMessage = 'UYARI: YETKİSİZ ARAÇ TESPİTİ!';
        _gateStatus = 'KAPALI - YETKİSİZ ERİŞİM';
      });
      await Future.delayed(Duration(milliseconds: 1000));

    } else {
      // Araç yok
      if (_currentPhase == 'detecting') {
        setState(() {
          _securityMessage = 'ARAÇ ARANILIYOR... Güvenlik Alanını Tarayın';
        });
      }
    }
  }

  // Frame yakala ve Flask sunucusuna gönder - Yüksek kalite
  Future<Map<String, dynamic>?> _captureAndAnalyzeFrame(Duration timestamp) async {
    try {
      // Video thumbnail oluştur - Yüksek kalite ayarları
      final thumbnailBytes = await VideoThumbnail.thumbnailData(
        video: _videoFile!.path,
        timeMs: timestamp.inMilliseconds,
        quality: 100, // Maksimum kalite
        maxWidth: 1920, // Full HD genişlik
        maxHeight: 1080, // Full HD yükseklik
      );

      if (thumbnailBytes != null) {
        final result = await _sendFrameToServer(thumbnailBytes, timestamp);
        return result;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  // Flask sunucusuna frame gönder - Kalite korunarak
  Future<Map<String, dynamic>?> _sendFrameToServer(Uint8List imageBytes, Duration timestamp) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$_serverUrl/detect'));
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'frame_${timestamp.inMilliseconds}.jpg',
      ));

      var streamedResponse = await request.send().timeout(Duration(seconds: 15));
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        return null;
      }

      final jsonData = json.decode(response.body);

      if (jsonData.containsKey('error')) {
        return {
          'status': 'error',
          'message': jsonData['error'],
          'timestamp': timestamp.inSeconds,
        };
      }

      return {
        'timestamp': timestamp.inSeconds,
        'status': jsonData['status'],
        'plate': jsonData['plate'],
        'warning': jsonData['warning'],
        'time_formatted': _formatDuration(timestamp),
      };
    } catch (e) {
      return null;
    }
  }

  void _stopSecurityScan() {
    setState(() {
      _isAnalyzing = false;
      _securityMessage = 'Güvenlik Taraması Durduruldu';
      _currentPhase = 'waiting';
      _gateStatus = 'KAPALI';
    });
  }

  void _resetGate() {
    setState(() {
      _resetSecuritySystem();
    });
  }

  Future<void> _loadRegisteredPlates() async {
    final prefs = await SharedPreferences.getInstance();
    final plates = prefs.getStringList('registered_plates') ?? [];
    setState(() {
      _registeredPlates = plates;
    });
  }

  bool _isPlateRegistered(String plate) {
    return _registeredPlates.contains(plate.toUpperCase());
  }

  Future<void> _sendGateCommand(String command) async {
    try {
      final response = await http.post(
        Uri.parse(_gateUrl),
        headers: {'Content-Type': 'text/plain'},
        body: command,
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('Kapı komutu gönderildi: $command');
      } else {
        print('Kapı komutu başarısız: ${response.statusCode}');
      }
    } catch (e) {
      print('Kapı kontrol hatası: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('GÜVENLİK KAPISI SİSTEMİ',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SettingsScreen()),
              );
              // Ayarlardan döndükten sonra kayıtlı plakaları yeniden yükle
              await _loadRegisteredPlates();
            },
            icon: Icon(Icons.settings),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Güvenlik Durumu Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _getStatusGradient(),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _getStatusIconMain(),
                        size: 32,
                        color: Colors.white,
                      ),
                      SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'KAPI DURUMU: $_gateStatus',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  if (_plateNumber.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        'PLAKA: $_plateNumber',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Video Player with Security Overlay
            if (_videoFile != null && _videoController != null) ...[
              Container(
                margin: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      // Video Player
                      AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
                      ),

                      // Security Overlay
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.7),
                                Colors.transparent,
                                Colors.transparent,
                                Colors.black.withOpacity(0.7),
                              ],
                              stops: [0.0, 0.3, 0.7, 1.0],
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Üst overlay - Güvenlik mesajı
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    // Ana güvenlik mesajı
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: _getMessageBackgroundColor().withOpacity(0.9),
                                        borderRadius: BorderRadius.circular(25),
                                        border: Border.all(
                                          color: _getMessageBorderColor(),
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black54,
                                            blurRadius: 8,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_isAnalyzing) ...[
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                          ],
                                          Icon(
                                            _getMessageIcon(),
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                          SizedBox(width: 12),
                                          Flexible(
                                            child: Text(
                                              _securityMessage,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                                letterSpacing: 0.5,
                                              ),
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // İlerleme çubuğu (analiz sırasında)
                                    if (_isAnalyzing && _totalFrames > 0) ...[
                                      SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: _analysisProgress,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.orange,
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Tarama: ${(_analysisProgress * 100).toStringAsFixed(0)}%',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              // Alt overlay - Video kontrolleri
                              Container(
                                padding: EdgeInsets.all(16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      onPressed: _playPauseVideo,
                                      icon: Icon(
                                        _videoController!.value.isPlaying
                                            ? Icons.pause_circle_filled
                                            : Icons.play_circle_filled,
                                        size: 48,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 20),
                                    IconButton(
                                      onPressed: () {
                                        _videoController!.seekTo(Duration.zero);
                                      },
                                      icon: Icon(
                                        Icons.replay,
                                        size: 32,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Kontrol Paneli
            Container(
              margin: EdgeInsets.all(16),
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[700]!),
              ),
              child: Column(
                children: [
                  Text(
                    'GÜVENLİK KONTROL PANELİ',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.1,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Kayıtlı Plaka Sayısı: ${_registeredPlates.length}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[400],
                    ),
                  ),
                  SizedBox(height: 20),

                  // Video seçim butonları
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _pickVideoFromGallery,
                          icon: Icon(Icons.video_library),
                          label: Text('Galeri'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[700],
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _pickVideoFromCamera,
                          icon: Icon(Icons.videocam),
                          label: Text('Kamera'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (_videoFile != null) ...[
                    SizedBox(height: 16),
                    // Ana kontrol butonları
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isAnalyzing ? null : _startSecurityScan,
                            icon: Icon(Icons.security),
                            label: Text('GÜVENLİK TARAMASI'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange[700],
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 15),
                            ),
                          ),
                        ),
                        if (_isAnalyzing) ...[
                          SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _stopSecurityScan,
                              icon: Icon(Icons.stop),
                              label: Text('DURDUR'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red[700],
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 15),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _resetGate,
                      icon: Icon(Icons.refresh),
                      label: Text('SİSTEMİ SIFIRLA'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[700],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Yükleme göstergesi
            if (_isLoading)
              Container(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.orange),
                    SizedBox(height: 16),
                    Text(
                      'Video hazırlanıyor...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),

            // Boş durum
            if (_videoFile == null && !_isLoading)
              Container(
                height: 300,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.security,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Güvenlik Kamerası Bekleniyor',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[400],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Kamyon tespit sistemi için video seçin',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Color> _getStatusGradient() {
    switch (_currentPhase) {
      case 'detecting':
        return [Colors.orange[600]!, Colors.orange[800]!];
      case 'verifying':
        return [Colors.blue[600]!, Colors.blue[800]!];
      case 'approved':
        return [Colors.green[600]!, Colors.green[800]!];
      case 'denied':
        return [Colors.red[600]!, Colors.red[800]!];
      case 'error':
        return [Colors.red[800]!, Colors.red[900]!];
      default:
        return [Colors.grey[700]!, Colors.grey[800]!];
    }
  }

  IconData _getStatusIconMain() {
    switch (_currentPhase) {
      case 'detecting':
        return Icons.radar;
      case 'verifying':
        return Icons.verified_user;
      case 'approved':
        return Icons.lock_open;
      case 'denied':
        return Icons.block;
      case 'error':
        return Icons.error;
      default:
        return Icons.lock;
    }
  }

  Color _getMessageBackgroundColor() {
    switch (_currentPhase) {
      case 'detecting':
        return Colors.orange[700]!;
      case 'verifying':
        return Colors.blue[700]!;
      case 'approved':
        return Colors.green[700]!;
      case 'denied':
        return Colors.red[700]!;
      case 'error':
        return Colors.red[800]!;
      default:
        return Colors.grey[700]!;
    }
  }

  Color _getMessageBorderColor() {
    switch (_currentPhase) {
      case 'detecting':
        return Colors.orange[300]!;
      case 'verifying':
        return Colors.blue[300]!;
      case 'approved':
        return Colors.green[300]!;
      case 'denied':
        return Colors.red[300]!;
      case 'error':
        return Colors.red[400]!;
      default:
        return Colors.grey[400]!;
    }
  }

  IconData _getMessageIcon() {
    switch (_currentPhase) {
      case 'detecting':
        return Icons.search;
      case 'verifying':
        return Icons.fact_check;
      case 'approved':
        return Icons.check_circle;
      case 'denied':
        return Icons.warning;
      case 'error':
        return Icons.error_outline;
      default:
        return Icons.info;
    }
  }
}