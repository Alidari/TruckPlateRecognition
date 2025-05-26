import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _registeredPlates = [];
  final TextEditingController _plateController = TextEditingController();
  final String _gateUrl = 'http://192.168.208.116/data';
  bool _isLoadingGate = false;

  @override
  void initState() {
    super.initState();
    _loadRegisteredPlates();
  }

  Future<void> _loadRegisteredPlates() async {
    final prefs = await SharedPreferences.getInstance();
    final plates = prefs.getStringList('registered_plates') ?? [];
    setState(() {
      _registeredPlates = plates;
    });
  }

  Future<void> _saveRegisteredPlates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('registered_plates', _registeredPlates);
  }

  void _addPlate() {
    final plate = _plateController.text.trim().toUpperCase();
    if (plate.isNotEmpty && !_registeredPlates.contains(plate)) {
      setState(() {
        _registeredPlates.add(plate);
      });
      _saveRegisteredPlates();
      _plateController.clear();
      _showSnackBar('Plaka eklendi: $plate', Colors.green);
    } else if (_registeredPlates.contains(plate)) {
      _showSnackBar('Bu plaka zaten kayıtlı!', Colors.orange);
    }
  }

  void _removePlate(String plate) {
    setState(() {
      _registeredPlates.remove(plate);
    });
    _saveRegisteredPlates();
    _showSnackBar('Plaka silindi: $plate', Colors.red);
  }

  Future<void> _sendGateCommand(String command) async {
    setState(() {
      _isLoadingGate = true;
    });

    try {
      final response = await http.post(
        Uri.parse(_gateUrl),
        headers: {'Content-Type': 'text/plain'},
        body: command,
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        _showSnackBar('Kapı komutu gönderildi: $command', Colors.green);
      } else {
        _showSnackBar('Kapı komutu başarısız: ${response.statusCode}', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Bağlantı hatası: $e', Colors.red);
    } finally {
      setState(() {
        _isLoadingGate = false;
      });
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('AYARLAR'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kayıtlı Plakalar Bölümü
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[700]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KAYITLI PLAKALAR',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.1,
                    ),
                  ),
                  SizedBox(height: 16),

                  // Plaka ekleme
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _plateController,
                          style: TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Plaka numarası (örn: 34ABC123)',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            border: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey[600]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey[600]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.blue),
                            ),
                          ),
                          onSubmitted: (_) => _addPlate(),
                        ),
                      ),
                      SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _addPlate,
                        icon: Icon(Icons.add),
                        label: Text('EKLE'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 20),

                  // Kayıtlı plakalar listesi
                  if (_registeredPlates.isEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[600]!, style: BorderStyle.solid),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.no_accounts,
                            size: 48,
                            color: Colors.grey[500],
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Henüz kayıtlı plaka yok',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Toplam ${_registeredPlates.length} kayıtlı plaka:',
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 12),
                    ...List.generate(_registeredPlates.length, (index) {
                      final plate = _registeredPlates[index];
                      return Container(
                        margin: EdgeInsets.only(bottom: 8),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[700]!),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.verified_user,
                              color: Colors.green[400],
                              size: 20,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                plate,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _removePlate(plate),
                              icon: Icon(
                                Icons.delete,
                                color: Colors.red[400],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),

            SizedBox(height: 24),

            // Debug Kapı Kontrol Bölümü
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[700]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bug_report,
                        color: Colors.orange[400],
                        size: 24,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'DEBUG - KAPI KONTROLÜ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[400],
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Manuel kapı kontrolü için kullanın.',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoadingGate ? null : () => _sendGateCommand('ON'),
                          icon: _isLoadingGate
                              ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                              : Icon(Icons.lock_open),
                          label: Text('KAPI AÇ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoadingGate ? null : () => _sendGateCommand('OFF'),
                          icon: _isLoadingGate
                              ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                              : Icon(Icons.lock),
                          label: Text('KAPI KAPAT'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[700],
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 12),

                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hedef URL:',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          _gateUrl,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }
}
