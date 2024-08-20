import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';  // 导入 fluttertoast

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter BLE Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: BleHome(),
    );
  }
}

class BleHome extends StatefulWidget {
  @override
  _BleHomeState createState() => _BleHomeState();
}

class _BleHomeState extends State<BleHome> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final List<DiscoveredDevice> _devices = []; // 保存扫描到的设备列表
  Stream<DiscoveredDevice>? _scanStream;
  DiscoveredDevice? _connectedDevice;
  bool _isScanning = false;
  Stream<List<int>>? _notificationStream;
  String _notificationData = '';
  QualifiedCharacteristic? _writeCharacteristic;
  late StreamSubscription<ConnectionStateUpdate> _connectionSubscription;
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // 请求Android 12及以上版本需要的蓝牙和位置相关权限
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.bluetooth,
      Permission.bluetoothAdvertise
    ].request();

    // 检查权限是否被授予
    bool allGranted = statuses.values.every((status) => status.isGranted);
    if (!allGranted) {
      // 显示提示信息或引导用户前往设置开启权限
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('需要权限'),
          content: Text('应用需要蓝牙和位置权限才能正常工作，请允许权限。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  void _startScan() {
    if (!_isScanning) {
      setState(() {
        _isScanning = true;
        _devices.clear();
        // _scanStream = _ble.scanForDevices(withServices: []).asBroadcastStream();
      });
      _ble.scanForDevices(withServices: []).listen((device) {
        if(device.name.isNotEmpty && !_devices.any((d) => d.id == device.id)){
          setState(() {
            _devices.add(device);
          });
        }
      }).onDone(() {
        setState(() {
          _isScanning = false;
        });
      });
    }
  }

  void _stopScan() {
    setState(() {
      _isScanning = false;
      // _scanStream = null;
    });
  }

  void _disconnectDevice() async {
    if (_connectedDevice != null) {
      await _connectionSubscription.cancel();  // 取消连接订阅以断开连接
      setState(() {
        _connectedDevice = null;
        _connectionState = DeviceConnectionState.disconnected;
      });

      // 显示 Toast 消息
      // Fluttertoast.showToast(
      //   msg: "连接已断开",
      //   toastLength: Toast.LENGTH_SHORT,
      //   gravity: ToastGravity.BOTTOM,
      //   timeInSecForIosWeb: 1,
      //   backgroundColor: Colors.black54,
      //   textColor: Colors.white,
      //   fontSize: 16.0,
      // );
    }
  }

  void _connectToDevice(DiscoveredDevice device) async {
    _connectionSubscription = _ble.connectToDevice(
      id: device.id,
      connectionTimeout: const Duration(seconds: 5),
    ).listen((ConnectionStateUpdate connectionStateUpdate) {
      setState(() {
        _connectionState = connectionStateUpdate.connectionState;
      });

      if (connectionStateUpdate.connectionState == DeviceConnectionState.connected) {
        _discoverServices(device);
        setState(() {
          _connectedDevice = device;
        });
        print('Connected to ${device.name}');
      }
    }, onError: (error) {
      print('Connection error: $error');
    });
  }

  void _discoverServices(DiscoveredDevice device) async{
    // 发现设备服务
    final services = await _ble.getDiscoveredServices(device.id);

    for (var service in services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.id.toString().toLowerCase() == '6e400003-b5a3-f393-e0a9-e50e24dcca9e') {
          print("找到接收数据服务");
          // 订阅特征通知
          _notificationStream = _ble.subscribeToCharacteristic(
            QualifiedCharacteristic(
              characteristicId: characteristic.id,
              serviceId: service.id,
              deviceId: device.id,
            ),
          );
          _notificationStream!.listen((data) {
            setState(() {
              _notificationData = 'Received data: ${data.toString()}';
              print(_notificationData);
            });
          });
          // break;
        }

        if (characteristic.id.toString().toLowerCase() == '6e400002-b5a3-f393-e0a9-e50e24dcca9e'){
          // 连接成功后的一秒钟发送 0x04
          Future.delayed(Duration(seconds: 1), () async {
            try {
              await _ble.writeCharacteristicWithResponse(
                QualifiedCharacteristic(
                  characteristicId: characteristic.id,
                  serviceId: service.id,
                  deviceId: device.id,
                ),
                value: [0x04], // 发送的数据
              );
              print('Successfully wrote 0x04 to characteristic');
            } catch (e) {
              print('Write error: $e');
            }
          });

          // 保存写特征
          setState(() {
            _writeCharacteristic = QualifiedCharacteristic(
              characteristicId: characteristic.id,
              serviceId: service.id,
              deviceId: device.id,
            );
          });
          // break;
        }
      }
    }
  }

  void _sendData() async {
    if (_writeCharacteristic != null) {
      try {
        await _ble.writeCharacteristicWithResponse(
          _writeCharacteristic!,
          value: [0x01], // 发送的数据
        );
        print('Successfully wrote 0x01 to characteristic');
      } catch (e) {
        print('Write error: $e');
      }
    } else {
      print('No characteristic available for writing');
    }
  }

  void _sendData2() async {
    if (_writeCharacteristic != null) {
      try {
        await _ble.writeCharacteristicWithResponse(
          _writeCharacteristic!,
          value: [0x02], // 发送的数据
        );
        print('Successfully wrote 0x02 to characteristic');
      } catch (e) {
        print('Write error: $e');
      }
    } else {
      print('No characteristic available for writing');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Flutter Reactive BLE Demo'),
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.search),
            onPressed: _isScanning ? _stopScan : _startScan,
          ),
        ],
      ),
      body: Center(
        child: Column(
          children: [
            Expanded(
              child: _devices.isEmpty
                  ? Center(child: Text('点击搜索按钮开始扫描。'))
                  : ListView.builder(
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  return ListTile(
                    title: Text(device.name.isNotEmpty
                        ? device.name
                        : 'Unnamed Device'),
                    subtitle: Text(device.id),
                    onTap: () => _connectToDevice(device),
                  );
                },
              ),
            ),
            if (_connectedDevice != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('已连接到设备: ${_connectedDevice!.name}'),
                    Text('连接状态: ${_connectionState.toString().split('.').last}'),
                  ],
                ),
              ),
            if (_notificationData.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('通知数据: $_notificationData'),
              ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround, // 按钮水平居中
                children: [
                  ElevatedButton(
                    onPressed: _sendData,
                    child: Text('发送 0x01'),
                  ),
                  SizedBox(height: 5), // 添加间隔
                  ElevatedButton(
                    onPressed: _sendData2,
                    child: Text('发送 0x02'),
                  ),
                  if (_connectedDevice != null) // 当有已连接的设备时显示断开连接按钮
                    ElevatedButton(
                      onPressed: _disconnectDevice,
                      child: Text('断开连接'),
                      style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
