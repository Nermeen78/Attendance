import './offline_page.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:barcode_scan/barcode_scan.dart';
import 'package:flutter/services.dart';
import '../model/session_model.dart';
import '../model/scan_model.dart';
import '../DB/Database.dart';
import '../scan_exceptions.dart';
import 'package:connectivity/connectivity.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_admob/firebase_admob.dart';

abstract class OfflinePageViewModel extends State<OfflinePage> {
  String scanResult = "Scan Error: Make sure you're scanning the right code";
  List<Scan> scanedList=[];
  FirebaseAuth auth = FirebaseAuth.instance;
  FirebaseUser mUser;
  BannerAd myBanner = BannerAd(
    adUnitId: "ca-app-pub-5308838739950508/3820629006",
    size: AdSize.smartBanner,
    listener: (MobileAdEvent event) {
      print("BannerAd event is $event");
    },
  );
  OfflinePageViewModel() {
    FirebaseAdMob.instance.initialize(appId: "ca-app-pub-5308838739950508~2647148134");
    myBanner
      ..load()
      ..show(
        anchorOffset: 60.0,
        anchorType: AnchorType.bottom,
      );
    getScans();
  }

  showMessageDialog(String title, String message) {}

  getScans() async {
    scanedList.clear();
    scanedList.addAll(await DBProvider.db.getAllScans());
    setState(() {
    });
  }
  Future scan() async {
    try {
      String barcode = await BarcodeScanner.scan();
      SessionModel session = SessionModel(barcode);
      var now = new DateTime.now();
      Scan scan =Scan(key: session.key, classKey: session.classKey, admin: session.admin, arrive: now.toIso8601String());
      DBProvider.db.newScan(scan);
      getScans();
      this.scanResult = "Scanned Successfully";
    } on PlatformException catch (e) {
      if (e.code == BarcodeScanner.CameraAccessDenied) {
        setState(() {
          this.scanResult = 'You did not grant the camera permission!';
        });
      } else {
        setState(() => this.scanResult = 'Unknown error: $e');
      }
    } on FormatException{
      setState(() => print('Scan Cancelled'));
    } catch (e) {
      setState(() => print('Unknown error: $e'));
    }
    showMessageDialog("scan", this.scanResult);
  }

  Future scanLeave(int index) async {
    try {
      String barcode = await BarcodeScanner.scan();
      SessionModel session = SessionModel(barcode);
      if(session.key!=scanedList[index].key) throw InvalidSessionException("This is not the same session you attended");
      var now = new DateTime.now();
      scanedList[index].leave = now.toIso8601String();
      DBProvider.db.addLeave(scanedList[index]);
      getScans();
      this.scanResult = "Scanned Successfully";
    } on PlatformException catch (e) {
      if (e.code == BarcodeScanner.CameraAccessDenied) {
        setState(() {
          this.scanResult = 'You did not grant the camera permission!';
        });
      } else {
        setState(() => this.scanResult = 'Unknown error: $e');
      }
    } on FormatException{
      setState(() => this.scanResult = 'Scan cancelled');
    } on InvalidSessionException {
      setState(() => this.scanResult = "This is not the same session you attended");
    } catch (e) {
      setState(() => this.scanResult = 'Unknown error: $e');
    }
    showMessageDialog("scan", this.scanResult);
  }

  deleteItem(int index) {
    DBProvider.db.deleteScan(scanedList[index].id);
    getScans();
  }

  testConnection() async {
    String message = "You are not connected to internet";
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.mobile) {
      message = "You are connected to mobile data";
    } else if (connectivityResult == ConnectivityResult.wifi) {
      message = "You are connected to wifi";
    }
    showMessageDialog("test", message);
  }

  registerMe(int index) async {
    String message = "";
    if(!(await isLoggedIn())) {
      message = "Not loggedin, login first";
    } else if(await isScanned(index)) {
      message = "You already registered this session, Delete this record";
    } else {
      DatabaseReference attendanceRef =  FirebaseDatabase.instance.reference().child("attendances").push();
      DatabaseReference sessionRef = FirebaseDatabase.instance.reference().child(scanedList[index].admin).child("classes")
              .child(scanedList[index].classKey).child("sessions").child(scanedList[index].key);
      await attendanceRef.set({
        "session": scanedList[index].key,
        "sessionClass": scanedList[index].classKey,
        "sessionAdmin": scanedList[index].admin,
        "user": mUser.uid,
        "arriveTime": scanedList[index].arrive,
        "leaveTime": scanedList[index].leave==null?"NULL":scanedList[index].leave
      });
      sessionRef.child("attended").push().set(attendanceRef.key);
      await FirebaseDatabase.instance.reference().child(mUser.uid).child("attended").push().set(attendanceRef.key);
      DBProvider.db.deleteScan(scanedList[index].id);
      message = "Synced with the cloud successfully";
      getScans();
    }
    showMessageDialog("result", message);
  }

  Future<bool> isLoggedIn() async {
    mUser = await auth.currentUser();
    return mUser!=null;
  }

  Future<bool> isScanned(int index) async {
    DatabaseReference session = FirebaseDatabase.instance.reference().child(scanedList[index].admin).child("classes")
              .child(scanedList[index].classKey).child("sessions").child(scanedList[index].key);
    DataSnapshot attendencies = await session.child("attended").once();
    Map<dynamic, dynamic> value = attendencies.value;
    if(value==null || value.isEmpty) return false;
    for(var key in value.keys) {
      DataSnapshot ref = await FirebaseDatabase.instance.reference().child("attendances").child(value[key]).once();
      if(ref.value["user"] == mUser.uid) {
        debugPrint(mUser.uid);
        debugPrint(ref.value["user"]);
        return true;
      }
    }
    return false;
  }

  
}