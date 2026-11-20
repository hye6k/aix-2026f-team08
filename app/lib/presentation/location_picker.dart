import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class SelectedLocation {
  const SelectedLocation(this.latitude, this.longitude, this.address);
  final double latitude;
  final double longitude;
  final String? address;
}

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.useCurrentLocation = false,
    this.initialLatitude,
    this.initialLongitude,
  });
  final bool useCurrentLocation;
  final double? initialLatitude;
  final double? initialLongitude;
  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _map = MapController();
  LatLng? _selected;
  bool _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selected = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    }
    if (widget.useCurrentLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _current();
      });
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _current() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('기기의 위치 서비스를 켜 주세요.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw StateError('위치 권한이 차단됐어요. 기기 설정에서 허용하거나 지도를 직접 선택해 주세요.');
      }
      if (permission == LocationPermission.denied) {
        throw StateError('위치 권한이 없어 현재 위치를 가져오지 못했어요. 지도를 직접 선택할 수 있어요.');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      final point = LatLng(p.latitude, p.longitude);
      setState(() {
        _selected = point;
        _message = '현재 위치의 정확도는 약 ${p.accuracy.round()}m예요. 지도에서 조정할 수 있어요.';
      });
      _map.move(point, 16);
    } on StateError catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = '현재 위치를 가져오지 못했어요. 잠시 후 다시 시도하거나 지도를 선택해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final point = _selected;
    if (point == null || _busy) return;
    setState(() {
      _busy = true;
      _message = '주소를 확인하고 있어요…';
    });
    String? address;
    try {
      final results = await Geocoding(locale: const Locale('ko'))
          .placemarkFromCoordinates(point.latitude, point.longitude)
          .timeout(const Duration(seconds: 8));
      if (results.isNotEmpty) {
        final p = results.first;
        final parts =
            [
                  p.administrativeArea,
                  p.locality,
                  p.subLocality,
                  p.thoroughfare,
                  p.subThoroughfare,
                ]
                .whereType<String>()
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
        if (parts.isNotEmpty) address = parts.join(' ');
      }
    } catch (_) {
      // 주소 조회에 실패해도 선택한 위치는 보존한다.
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      SelectedLocation(point.latitude, point.longitude, address),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('위치 선택')),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text('지도를 눌러 장소를 선택하세요. 현재 위치를 가져온 뒤 위치를 조정할 수도 있어요.'),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _selected ?? const LatLng(37.5665, 126.9780),
                    initialZoom: _selected == null ? 11 : 16,
                    onTap: (_, point) {
                      if (!_busy) {
                        setState(() {
                          _selected = point;
                          _message = null;
                        });
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'io.github.hye6k.morning_routine',
                      maxZoom: 19,
                    ),
                    if (_selected != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _selected!,
                            width: 44,
                            height: 44,
                            child: const Icon(
                              Icons.location_pin,
                              size: 44,
                              color: Color(0xffb84033),
                            ),
                          ),
                        ],
                      ),
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'current-location',
                    onPressed: _busy ? null : _current,
                    tooltip: '현재 위치',
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_message!),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _selected == null || _busy ? null : _confirm,
                  child: Text(_busy ? '확인 중…' : '이 위치 선택'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
