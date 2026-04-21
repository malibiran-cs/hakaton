import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

// ─── Design tokens ────────────────────────────────────────────────────────────
class AppColors {
  static const teal = Color(0xFF1D9E75);
  static const tealLight = Color(0xFFEAF3DE);
  static const tealDark = Color(0xFF0F6E56);
  static const amber = Color(0xFFEF9F27);
  static const danger = Color(0xFFE24B4A);
  static const info = Color(0xFF378ADD);
  static const purple = Color(0xFF8B5CF6);
  static const surface = Color(0xFFF7F7F5);
  static const border = Color(0xFFE5E5E5);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CICS Inclusive Map',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.teal),
        useMaterial3: true,
        chipTheme: const ChipThemeData(
          selectedColor: Color(0xFFD4F0E5),
          labelStyle: TextStyle(fontSize: 12),
        ),
      ),
      home: const MapScreen(),
    );
  }
}

// ─── Enums ─────────────────────────────────────────────────────────────────────
enum RoomType { classroom, lab, office, toilet, utility }

enum AppMode {
  normal,
  emergency,
  pwd;

  String get label => switch (this) {
        AppMode.normal => 'Map',
        AppMode.emergency => 'Emergency',
        AppMode.pwd => 'PWD Route',
      };

  IconData get icon => switch (this) {
        AppMode.normal => Icons.map_outlined,
        AppMode.emergency => Icons.warning_amber_rounded,
        AppMode.pwd => Icons.accessible_forward_rounded,
      };
}

enum DisabilityMode {
  none,
  mobility,
  visual,
  hearing;

  String get label => switch (this) {
        DisabilityMode.none => 'Off',
        DisabilityMode.mobility => 'Mobility / Wheelchair',
        DisabilityMode.visual => 'Visual Impairment',
        DisabilityMode.hearing => 'Hearing Impairment',
      };

  IconData get icon => switch (this) {
        DisabilityMode.none => Icons.close,
        DisabilityMode.mobility => Icons.accessible_rounded,
        DisabilityMode.visual => Icons.visibility_off_outlined,
        DisabilityMode.hearing => Icons.hearing_disabled_outlined,
      };
}

// ─── Models (unchanged + toJson/fromJson added) ────────────────────────────────
class RoomData {
  final String name;
  final RoomType type;
  final double widthFactor;
  final String? badge;
  const RoomData({
    required this.name,
    required this.type,
    this.widthFactor = 1.0,
    this.badge,
  });
}

class FloorData {
  final int number;
  final String label;
  final List<RoomData> rooms;
  final bool stairsLeft;
  final bool stairsRight;
  const FloorData({
    required this.number,
    required this.label,
    required this.rooms,
    this.stairsLeft = true,
    this.stairsRight = true,
  });
}

class PWDReport {
  final String id;
  final int floor;
  final String location;
  final String issueType;
  final String description;
  final String severity;
  final double xNorm;

  const PWDReport({
    required this.id,
    required this.floor,
    required this.location,
    required this.issueType,
    required this.description,
    required this.severity,
    required this.xNorm,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'floor': floor,
        'location': location,
        'issue_type': issueType,
        'description': description,
        'severity': severity,
        'x_norm': xNorm,
      };

  static PWDReport fromJson(Map<String, dynamic> m) => PWDReport(
        id: m['id'].toString(),
        floor: m['floor'] as int,
        location: m['location'] as String,
        issueType: m['issue_type'] as String,
        description: m['description'] as String,
        severity: m['severity'] as String,
        xNorm: (m['x_norm'] as num).toDouble(),
      );

  Color get issueColor => switch (issueType) {
        'ramp' => AppColors.teal,
        'stairs' => AppColors.amber,
        'hazard' => AppColors.danger,
        'exit' => AppColors.info,
        'noise' => AppColors.purple,
        _ => Colors.grey,
      };

  Color get severityColor => switch (severity) {
        'high' => AppColors.danger,
        'medium' => AppColors.amber,
        _ => AppColors.teal,
      };

  String get semanticDescription =>
      '$issueType issue at $location on floor $floor. $description. Severity: $severity.';
}

class FloorRoute {
  final double startX;
  final double endX;
  final String note;
  const FloorRoute({
    required this.startX,
    required this.endX,
    required this.note,
  });
}

// ─── Service layer with persistence ───────────────────────────────────────────
class ReportService {
  static final ReportService _instance = ReportService._();
  factory ReportService() => _instance;
  ReportService._() {
    _reports.addAll(kInitialReports);
  }

  static const _prefsKey = 'pwd_reports_v1';
  final List<PWDReport> _reports = [];

  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      // Only add if id not already present (don't duplicate seed data)
      final existing = _reports.map((r) => r.id).toSet();
      for (final m in list) {
        final r = PWDReport.fromJson(m);
        if (!existing.contains(r.id)) _reports.add(r);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Only persist user-submitted reports (not seed data)
      final userReports = _reports
          .where((r) => !r.id.startsWith('r') || r.id.length > 2)
          .map((r) => r.toJson())
          .toList();
      await prefs.setString(_prefsKey, jsonEncode(userReports));
    } catch (_) {}
  }

  List<PWDReport> getAllReports() => List.unmodifiable(_reports);
  List<PWDReport> getFloorReports(int floor) =>
      _reports.where((r) => r.floor == floor).toList();

  Future<void> submitReport(PWDReport report) async {
    _reports.add(report);
    await _save();
  }
}

// ─── Floor data (unchanged from original) ─────────────────────────────────────
const List<FloorData> kFloors = [
  FloorData(
    number: 1,
    label: 'Ground Floor',
    rooms: [
      RoomData(name: "Women's\nToilet", type: RoomType.toilet),
      RoomData(name: 'CICS Orgs\nOffice', type: RoomType.office, badge: '★'),
      RoomData(name: '101', type: RoomType.classroom),
      RoomData(name: '102', type: RoomType.classroom),
      RoomData(name: '103', type: RoomType.classroom),
      RoomData(name: '104', type: RoomType.classroom),
      RoomData(name: '105', type: RoomType.classroom),
      RoomData(name: '106', type: RoomType.classroom),
      RoomData(name: 'Faculty\nToilet', type: RoomType.toilet),
      RoomData(name: 'Utility\nRoom', type: RoomType.utility, badge: '⚙'),
    ],
  ),
  FloorData(
    number: 2,
    label: '2nd Floor',
    rooms: [
      RoomData(name: 'Faculty\nToilet', type: RoomType.toilet),
      RoomData(name: '201', type: RoomType.classroom),
      RoomData(name: '202', type: RoomType.classroom),
      RoomData(name: 'CPE\nFaculty', type: RoomType.office, badge: 'A'),
      RoomData(name: 'Student\nServices', type: RoomType.office, badge: 'B', widthFactor: 1.4),
      RoomData(name: 'Consult\nOffice', type: RoomType.office, badge: 'C', widthFactor: 1.2),
      RoomData(name: 'CICS\nFaculty', type: RoomType.office, badge: 'D'),
      RoomData(name: "Dean's\nOffice", type: RoomType.office, badge: 'E'),
      RoomData(name: 'Faculty\nToilet', type: RoomType.toilet),
    ],
  ),
  FloorData(
    number: 3,
    label: '3rd Floor',
    rooms: [
      RoomData(name: "Women's\nToilet", type: RoomType.toilet),
      RoomData(name: 'LAB 1', type: RoomType.lab),
      RoomData(name: 'LAB 2', type: RoomType.lab),
      RoomData(name: 'LAB 3', type: RoomType.lab),
      RoomData(name: 'LAB 4', type: RoomType.lab),
      RoomData(name: 'LAB 5', type: RoomType.lab),
      RoomData(name: 'LAB 6', type: RoomType.lab),
      RoomData(name: "Men's\nToilet", type: RoomType.toilet),
    ],
  ),
  FloorData(
    number: 4,
    label: '4th Floor',
    rooms: [
      RoomData(name: '401', type: RoomType.classroom),
      RoomData(name: '402', type: RoomType.classroom),
      RoomData(name: 'Physics\nLab', type: RoomType.lab, widthFactor: 1.2),
      RoomData(name: 'SMART', type: RoomType.lab, widthFactor: 1.2),
      RoomData(name: 'EDL', type: RoomType.lab),
      RoomData(name: 'Tech\nLab', type: RoomType.lab, badge: 'F'),
      RoomData(name: 'ITL', type: RoomType.lab),
    ],
  ),
  FloorData(
    number: 5,
    label: '5th Floor',
    rooms: [
      RoomData(name: '501', type: RoomType.classroom),
      RoomData(name: '502', type: RoomType.classroom),
      RoomData(name: '503', type: RoomType.classroom),
      RoomData(name: '504', type: RoomType.classroom),
      RoomData(name: '505', type: RoomType.classroom),
      RoomData(name: '506', type: RoomType.classroom),
    ],
  ),
];

// ─── Route data (unchanged from original) ─────────────────────────────────────
const Map<int, FloorRoute> kPwdRoutes = {
  1: FloorRoute(startX: 0.08, endX: 0.90, note: 'Entrance ramp (left) → accessible corridor → right exit'),
  2: FloorRoute(startX: 0.04, endX: 0.92, note: 'Left stairwell (from ramp side) → corridor → destination'),
  3: FloorRoute(startX: 0.04, endX: 0.92, note: 'Continue via left stairwell → traverse corridor'),
  4: FloorRoute(startX: 0.94, endX: 0.08, note: 'Right stairwell only → corridor'),
  5: FloorRoute(startX: 0.10, endX: 0.90, note: 'No stairwells on this floor — traverse corridor'),
};

const Map<int, FloorRoute> kEmergencyRoutes = {
  1: FloorRoute(startX: 0.50, endX: 0.94, note: 'Evacuate → main exit at right end of building'),
  2: FloorRoute(startX: 0.50, endX: 0.04, note: 'Left stairwell → descend → main exit'),
  3: FloorRoute(startX: 0.50, endX: 0.04, note: 'Left stairwell → descend → main exit'),
  4: FloorRoute(startX: 0.50, endX: 0.94, note: 'Right stairwell → descend → main exit'),
  5: FloorRoute(startX: 0.50, endX: 0.94, note: 'Move right → use floor 4 stairwell → exit'),
};

const Map<int, FloorRoute> kVisualRoutes = {
  1: FloorRoute(startX: 0.08, endX: 0.50, note: 'Follow wall edge → stay centered → avoid crowded exits'),
  2: FloorRoute(startX: 0.04, endX: 0.50, note: 'Keep left wall → move toward central offices'),
  3: FloorRoute(startX: 0.04, endX: 0.50, note: 'Use wall guidance → avoid lab congestion'),
  4: FloorRoute(startX: 0.94, endX: 0.50, note: 'Use right-side landmarks → central corridor'),
  5: FloorRoute(startX: 0.10, endX: 0.50, note: 'Straight corridor path → minimal turns'),
};

const Map<int, FloorRoute> kHearingRoutes = {
  1: FloorRoute(startX: 0.50, endX: 0.93, note: 'Proceed to visible exit signage (right side)'),
  2: FloorRoute(startX: 0.50, endX: 0.04, note: 'Move to stairwell with visible exit indicators'),
  3: FloorRoute(startX: 0.50, endX: 0.04, note: 'Follow visual exit signs → left stairwell'),
  4: FloorRoute(startX: 0.50, endX: 0.94, note: 'Right stairwell (clear visibility path)'),
  5: FloorRoute(startX: 0.50, endX: 0.94, note: 'Proceed to nearest visible exit route'),
};

const Map<int, List<(String, double)>> kFloorLocations = {
  1: [
    ("Main Entrance / Ramp", 0.07), ("Women's Toilet", 0.04), ("CICS Orgs Office", 0.15),
    ("Room 101 Entrance", 0.25), ("Room 102 Entrance", 0.34), ("Room 103 Entrance", 0.43),
    ("Room 104 Entrance", 0.52), ("Room 105 Entrance", 0.62), ("Room 106 Entrance", 0.72),
    ("Faculty Toilet", 0.83), ("Utility Room / Right Exit", 0.93),
  ],
  2: [
    ("Left Stairwell", 0.03), ("Faculty Toilet (Left)", 0.07), ("Room 201 Entrance", 0.18),
    ("Room 202 Entrance", 0.28), ("CPE Faculty (A)", 0.38), ("Student Services (B)", 0.50),
    ("Consultation Office (C)", 0.62), ("CICS Faculty (D)", 0.74), ("Dean's Office (E)", 0.84),
    ("Faculty Toilet (Right)", 0.93), ("Right Stairwell", 0.97),
  ],
  3: [
    ("Left Stairwell", 0.03), ("Women's Toilet", 0.07), ("Lab 1 Entrance", 0.20),
    ("Lab 2 Entrance", 0.32), ("Lab 3 Entrance", 0.44), ("Lab 4 Entrance", 0.56),
    ("Lab 5 Entrance", 0.68), ("Lab 6 Entrance", 0.80), ("Men's Toilet", 0.91),
    ("Right Stairwell", 0.97),
  ],
  4: [
    ("Room 401 Entrance", 0.10), ("Room 402 Entrance", 0.22), ("Physics Lab Entrance", 0.35),
    ("SMART Classroom", 0.50), ("EDL Entrance", 0.63), ("Tech Lab (F) Entrance", 0.75),
    ("ITL Entrance", 0.87), ("Right Stairwell", 0.97),
  ],
  5: [
    ("Room 501 Entrance", 0.10), ("Room 502 Entrance", 0.25), ("Room 503 Entrance", 0.40),
    ("Room 504 Entrance", 0.55), ("Room 505 Entrance", 0.70), ("Room 506 Entrance", 0.85),
  ],
};

const List<PWDReport> kInitialReports = [
  PWDReport(id: 'r1', floor: 1, location: 'Main Entrance / Ramp', issueType: 'ramp', description: 'Ramp surface is slippery when wet — use caution', severity: 'high', xNorm: 0.07),
  PWDReport(id: 'r2', floor: 1, location: 'Utility Room / Right Exit', issueType: 'exit', description: 'Exit accessible — door width OK for standard wheelchair', severity: 'low', xNorm: 0.93),
  PWDReport(id: 'r3', floor: 2, location: "Dean's Office (E)", issueType: 'hazard', description: "Narrow corridor — difficult for large wheelchairs", severity: 'medium', xNorm: 0.84),
  PWDReport(id: 'r4', floor: 2, location: 'Left Stairwell', issueType: 'stairs', description: 'No handrail on right side of stairwell', severity: 'medium', xNorm: 0.03),
  PWDReport(id: 'r5', floor: 3, location: 'Left Stairwell', issueType: 'stairs', description: 'Steep stairwell — no accessible alternative', severity: 'high', xNorm: 0.03),
  PWDReport(id: 'r6', floor: 3, location: 'Lab 4 Entrance', issueType: 'hazard', description: 'Door threshold too high — difficult for wheelchair entry', severity: 'high', xNorm: 0.56),
];

const Map<int, (String, Color, Color)> kFloorRanking = {
  1: ('Accessible (9.5)', Color(0xFF27724A), Color(0xFFDEF2E8)),
  2: ('Fair (7.0)', Color(0xFF7A4A0A), Color(0xFFFFF0D8)),
  3: ('Limited (5.2)', Color(0xFF8B1F1F), Color(0xFFFDE8E8)),
  4: ('Fair (6.8)', Color(0xFF7A4A0A), Color(0xFFFFF0D8)),
  5: ('Accessible (9.0)', Color(0xFF27724A), Color(0xFFDEF2E8)),
};

// ─── Helpers ──────────────────────────────────────────────────────────────────
String _roomTypeLabel(RoomType t) => switch (t) {
      RoomType.classroom => 'Classroom',
      RoomType.lab => 'Computer Laboratory',
      RoomType.office => 'Office',
      RoomType.toilet => 'Comfort Room',
      RoomType.utility => 'Utility Room',
    };

String _roomAccessibility(RoomType t) => switch (t) {
      RoomType.classroom => 'Standard door width. Check for step-free entry.',
      RoomType.lab => 'Lab entrance may have raised threshold — report if issue.',
      RoomType.office => 'Office corridors may be narrow for large wheelchairs.',
      RoomType.toilet => 'Check for PWD-compliant grab bars and turning space.',
      RoomType.utility => 'Staff access only.',
    };

// ─── Main screen ──────────────────────────────────────────────────────────────
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  int _floorIndex = 0;
  AppMode _mode = AppMode.normal;
  DisabilityMode _disability = DisabilityMode.none;
  PWDReport? _selectedReport;
  RoomData? _selectedRoom;
  String? _hoverLabel;
  Offset? _hoverLocalOffset;
  bool _hasSeenOnboarding = false;

  final _transformController = TransformationController();
  final _reportService = ReportService();

  late final AnimationController _popupAnimController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _popupAnim =
      CurvedAnimation(parent: _popupAnimController, curve: Curves.easeOut);

  static const double _mapHeight = 220.0;
  static const double _corridorH = 35.0;
  static const double _stairsW = 22.0;

  FloorData get _floor => kFloors[_floorIndex];
  List<PWDReport> get _floorReports => _reportService.getFloorReports(_floor.number);

  @override
  void initState() {
    super.initState();
    _reportService.loadFromPrefs().then((_) => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _showOnboardingIfNeeded());
  }

  @override
  void dispose() {
    _transformController.dispose();
    _popupAnimController.dispose();
    super.dispose();
  }

  void _showOnboardingIfNeeded() {
    if (_hasSeenOnboarding) return;
    _hasSeenOnboarding = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _OnboardingDialog(),
    );
  }

  List<(RoomData, Rect)> _computeRoomRects(double mapWidth) {
    const roomH = _mapHeight - _corridorH;
    final roomStartX = _floor.stairsLeft ? _stairsW : 4.0;
    final roomEndX = _floor.stairsRight ? mapWidth - _stairsW : mapWidth - 4.0;
    final totalFactor = _floor.rooms.fold(0.0, (double s, RoomData r) => s + r.widthFactor);
    final unitW = (roomEndX - roomStartX) / totalFactor;
    final result = <(RoomData, Rect)>[];
    double x = roomStartX;
    for (final room in _floor.rooms) {
      final rw = unitW * room.widthFactor;
      result.add((room, Rect.fromLTWH(x + 1, 4, rw - 2, roomH - 8)));
      x += rw;
    }
    return result;
  }

  void _handleTap(Offset localOffset, double mapWidth) {
    final sceneOffset = _transformController.toScene(localOffset);
    const roomH = _mapHeight - _corridorH;

    for (final report in _floorReports) {
      final mx = report.xNorm * mapWidth;
      final my = roomH / 2;
      if ((sceneOffset.dx - mx).abs() < 22 && (sceneOffset.dy - my).abs() < 22) {
        setState(() {
          _selectedReport = (_selectedReport?.id == report.id) ? null : report;
          _selectedRoom = null;
        });
        if (_selectedReport != null) {
          _popupAnimController.forward(from: 0);
        }
        return;
      }
    }

    final rects = _computeRoomRects(mapWidth);
    for (final (room, rect) in rects) {
      if (rect.contains(sceneOffset)) {
        setState(() {
          _selectedRoom = (_selectedRoom == room) ? null : room;
          _selectedReport = null;
        });
        if (_selectedRoom != null) {
          _popupAnimController.forward(from: 0);
        }
        return;
      }
    }

    setState(() {
      _selectedReport = null;
      _selectedRoom = null;
    });
  }

  void _handleHover(Offset localOffset, double mapWidth) {
    // Convert cursor point to the map's scene coordinates so hover hit-testing
    // stays correct while zoomed/panned.
    final sceneOffset = _transformController.toScene(localOffset);
    const roomH = _mapHeight - _corridorH;

    String? nextLabel;

    for (final report in _floorReports) {
      final mx = report.xNorm * mapWidth;
      final my = roomH / 2;
      if ((sceneOffset.dx - mx).abs() < 22 && (sceneOffset.dy - my).abs() < 22) {
        final tag = report.issueType == 'hazard'
            ? '!'
            : report.issueType[0].toUpperCase();
        final label = switch (report.issueType) {
          'ramp' => 'Ramp',
          'stairs' => 'Stairs',
          'hazard' => 'Hazard',
          'exit' => 'Exit',
          'noise' => 'Noise',
          _ => report.issueType,
        };
        nextLabel = '$tag = $label · ${report.location}';
        break;
      }
    }

    if (nextLabel == null) {
      final rects = _computeRoomRects(mapWidth);
      for (final (room, rect) in rects) {
        if (rect.contains(sceneOffset)) {
          if (room.badge != null) {
            const bR = 9.0;
            final badgeCenter =
                Offset(rect.right - bR - 2, rect.top + bR + 3);
            if ((sceneOffset - badgeCenter).distance <= bR + 2) {
              final roomName = room.name.replaceAll('\n', ' ');
              nextLabel = 'Badge ${room.badge}: $roomName';
              break;
            }
          }
          final roomName = room.name.replaceAll('\n', ' ');
          nextLabel = '$roomName · ${_roomTypeLabel(room.type)}';
          break;
        }
      }
    }

    if (nextLabel == _hoverLabel &&
        _hoverLocalOffset != null &&
        (localOffset - _hoverLocalOffset!).distance < 2) {
      return;
    }

    setState(() {
      _hoverLabel = nextLabel;
      _hoverLocalOffset = nextLabel == null ? null : localOffset;
    });
  }

  void _changeFloor(int i) {
    setState(() {
      _floorIndex = i;
      _selectedReport = null;
      _selectedRoom = null;
      _transformController.value = Matrix4.identity();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ranking = kFloorRanking[_floor.number]!;
    final reportCount = _floorReports.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CICS Inclusive Map',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text('${_floor.label} · $reportCount report${reportCount == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          Tooltip(
            message: 'Reset zoom',
            child: IconButton(
              icon: const Icon(Icons.zoom_out_map_rounded),
              onPressed: () => setState(() {
                _transformController.value = Matrix4.identity();
                _selectedReport = null;
                _selectedRoom = null;
              }),
            ),
          ),
          _DisabilityPicker(
            current: _disability,
            onChanged: (d) => setState(() => _disability = d),
          ),
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1, color: AppColors.border),
          _FloorSelector(selected: _floorIndex, onChanged: _changeFloor),
          _ModeToggle(current: _mode, onChanged: (m) => setState(() {
            _mode = m;
            _selectedReport = null;
            _selectedRoom = null;
          })),
          _LegendBar(),
          // Accessibility score banner
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
            color: ranking.$3,
            child: Row(
              children: [
                Icon(Icons.verified_rounded, size: 13, color: ranking.$2),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Floor ${_floor.number} accessibility: ${ranking.$1}',
                    style: TextStyle(
                      fontSize: 11,
                      color: ranking.$2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_mode != AppMode.normal)
            _RouteBanner(mode: _mode, floor: _floor.number, disability: _disability),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, outer) {
                final mapWidth = outer.maxWidth - 24;
                return Stack(
                  children: [
                    MouseRegion(
                      onExit: (_) {
                        if (_hoverLabel != null) {
                          setState(() {
                            _hoverLabel = null;
                            _hoverLocalOffset = null;
                          });
                        }
                      },
                      onHover: (e) => _handleHover(e.localPosition, mapWidth),
                      child: GestureDetector(
                        onTapDown: (d) => _handleTap(d.localPosition, mapWidth),
                        child: InteractiveViewer(
                          transformationController: _transformController,
                          boundaryMargin: const EdgeInsets.all(80),
                          minScale: 0.5,
                          maxScale: 6.0,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 16),
                              child: SizedBox(
                                width: mapWidth,
                                height: _mapHeight,
                                // RepaintBoundary: prevents the map from repainting
                                // when only the popups or banners change
                                child: RepaintBoundary(
                                  child: Semantics(
                                    label:
                                        'Floor plan of ${_floor.label}. '
                                        'Tap a room to see accessibility details. '
                                        'Tap a marker to see a reported issue.',
                                    child: CustomPaint(
                                      painter: FloorPlanPainter(
                                        floor: _floor,
                                        mode: _mode,
                                        disability: _disability,
                                        reports: _floorReports,
                                        selected: _selectedReport,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_hoverLabel != null && _hoverLocalOffset != null)
                      Positioned(
                        left: (_hoverLocalOffset!.dx + 12)
                            .clamp(8.0, outer.maxWidth - 240),
                        top: (_hoverLocalOffset!.dy + 10)
                            .clamp(8.0, outer.maxHeight - 60),
                        child: IgnorePointer(
                          child: Material(
                            color: Colors.transparent,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.82),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                child: Text(
                                  _hoverLabel!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_selectedReport != null)
                      Positioned(
                        bottom: 20,
                        left: 20,
                        right: 20,
                        child: FadeTransition(
                          opacity: _popupAnim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.15),
                              end: Offset.zero,
                            ).animate(_popupAnim),
                            child: _ReportPopup(
                              report: _selectedReport!,
                              onClose: () => setState(() => _selectedReport = null),
                            ),
                          ),
                        ),
                      ),
                    if (_selectedRoom != null)
                      Positioned(
                        bottom: 20,
                        left: 20,
                        right: 20,
                        child: FadeTransition(
                          opacity: _popupAnim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.15),
                              end: Offset.zero,
                            ).animate(_popupAnim),
                            child: _RoomInfoPopup(
                              room: _selectedRoom!,
                              floor: _floor,
                              onClose: () => setState(() => _selectedRoom = null),
                            ),
                          ),
                        ),
                      ),
                    if (_disability != DisabilityMode.none)
                      _DisabilityBanner(mode: _disability),
                  ],
                );
              },
            ),
          ),
          _RankingBar(currentFloor: _floor.number),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSubmitDialog(context),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Report issue'),
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        tooltip: 'Submit a PWD accessibility issue on this floor',
      ),
    );
  }

  void _showSubmitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _ReportDialog(
        floor: _floor,
        onSubmit: (report) async {
          await _reportService.submitReport(report);
          setState(() {});
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Report submitted — ${report.location}, Floor ${report.floor}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.teal,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        },
      ),
    );
  }
}

// ─── Onboarding dialog ────────────────────────────────────────────────────────
class _OnboardingDialog extends StatelessWidget {
  const _OnboardingDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.tealLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.accessible_forward_rounded,
                color: AppColors.teal, size: 20),
          ),
          const SizedBox(width: 10),
          const Text('Welcome', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This app helps PWD students navigate the CICS building safely.',
            style: TextStyle(fontSize: 13),
          ),
          SizedBox(height: 14),
          _OnboardingTip(
            icon: Icons.map_outlined,
            color: AppColors.info,
            title: 'Map mode',
            body: 'Tap any room to see its accessibility information.',
          ),
          _OnboardingTip(
            icon: Icons.accessible_forward_rounded,
            color: AppColors.teal,
            title: 'PWD Route',
            body: 'Shows the recommended accessible path on each floor.',
          ),
          _OnboardingTip(
            icon: Icons.warning_amber_rounded,
            color: AppColors.danger,
            title: 'Emergency',
            body: 'Highlights the fastest safe evacuation route.',
          ),
          _OnboardingTip(
            icon: Icons.add_location_alt_outlined,
            color: AppColors.purple,
            title: 'Report issues',
            body: 'Tap the button below to flag accessibility problems.',
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teal,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text("Let's go"),
        ),
      ],
    );
  }
}

class _OnboardingTip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _OnboardingTip(
      {required this.icon,
      required this.color,
      required this.title,
      required this.body});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                    fontSize: 12, color: Colors.black87, height: 1.5),
                children: [
                  TextSpan(
                      text: '$title — ',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Floor selector ───────────────────────────────────────────────────────────
class _FloorSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const _FloorSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      color: AppColors.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: kFloors.length,
        itemBuilder: (_, i) {
          final floor = kFloors[i];
          final isSelected = selected == i;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Semantics(
              label: '${floor.label}, floor ${floor.number}',
              selected: isSelected,
              button: true,
              child: ChoiceChip(
                label: Text(floor.label),
                selected: isSelected,
                onSelected: (_) => onChanged(i),
                selectedColor: AppColors.tealLight,
                checkmarkColor: AppColors.tealDark,
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? AppColors.tealDark : Colors.grey[700],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Mode toggle ──────────────────────────────────────────────────────────────
class _ModeToggle extends StatelessWidget {
  final AppMode current;
  final ValueChanged<AppMode> onChanged;
  const _ModeToggle({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: AppMode.values.map((m) {
          final active = current == m;
          final color = m == AppMode.emergency ? AppColors.danger : AppColors.teal;
          return Expanded(
            child: Semantics(
              label: '${m.label} mode',
              selected: active,
              button: true,
              child: InkWell(
                onTap: () => onChanged(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: active ? color : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(m.icon,
                          size: 15,
                          color: active ? color : Colors.grey[400]),
                      const SizedBox(width: 5),
                      Text(
                        m.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: active ? color : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Legend bar ───────────────────────────────────────────────────────────────
class _LegendBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Map legend: green for ramp, orange for stairs, red for hazard, blue for exit',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _LegendDot(color: AppColors.teal, label: 'Ramp'),
              _LegendDot(color: AppColors.amber, label: 'Stairs'),
              _LegendDot(color: AppColors.danger, label: 'Hazard'),
              _LegendDot(color: AppColors.info, label: 'Exit'),
              _LegendDot(color: AppColors.purple, label: 'Noise'),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
        ],
      ),
    );
  }
}

// ─── Route banner ─────────────────────────────────────────────────────────────
class _RouteBanner extends StatelessWidget {
  final AppMode mode;
  final int floor;
  final DisabilityMode disability;
  const _RouteBanner(
      {required this.mode, required this.floor, required this.disability});

  FloorRoute? _resolveRoute() {
    if (mode == AppMode.pwd) {
      return switch (disability) {
        DisabilityMode.visual => kVisualRoutes[floor],
        DisabilityMode.hearing => kHearingRoutes[floor],
        _ => kPwdRoutes[floor],
      };
    }
    return kEmergencyRoutes[floor];
  }

  @override
  Widget build(BuildContext context) {
    final route = _resolveRoute();
    if (route == null) return const SizedBox.shrink();
    final isPwd = mode == AppMode.pwd;
    final color = isPwd ? AppColors.teal : AppColors.danger;
    final bg = isPwd ? AppColors.tealLight : const Color(0xFFFDE8E8);

    return Semantics(
      label: '${isPwd ? 'PWD route' : 'Emergency route'}: ${route.note}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        color: bg,
        child: Row(
          children: [
            Icon(mode.icon, size: 13, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                route.note,
                style: TextStyle(
                    fontSize: 10, color: color, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Report popup ─────────────────────────────────────────────────────────────
class _ReportPopup extends StatelessWidget {
  final PWDReport report;
  final VoidCallback onClose;
  const _ReportPopup({required this.report, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: report.semanticDescription,
      child: Card(
        elevation: 8,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: report.issueColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(report.location,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  Semantics(
                    label: 'Close popup',
                    button: true,
                    child: GestureDetector(
                      onTap: onClose,
                      child: const Icon(Icons.close, size: 18, color: Colors.grey),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(report.description,
                  style:
                      const TextStyle(fontSize: 12, color: Colors.black87, height: 1.4)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Chip(
                    label:
                        '${report.severity[0].toUpperCase()}${report.severity.substring(1)} severity',
                    color: report.severityColor,
                  ),
                  const SizedBox(width: 6),
                  _Chip(label: 'Floor ${report.floor}', color: Colors.grey),
                  const SizedBox(width: 6),
                  _Chip(label: report.issueType, color: report.issueColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w500)),
    );
  }
}

// ─── Room info popup ──────────────────────────────────────────────────────────
class _RoomInfoPopup extends StatelessWidget {
  final RoomData room;
  final FloorData floor;
  final VoidCallback onClose;
  const _RoomInfoPopup(
      {required this.room, required this.floor, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final name = room.name.replaceAll('\n', ' ');
    return Semantics(
      label:
          '$name. ${_roomTypeLabel(room.type)} on floor ${floor.number}. ${_roomAccessibility(room.type)}',
      child: Card(
        elevation: 8,
        shadowColor: Colors.black26,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.meeting_room_outlined,
                      size: 16, color: AppColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  Semantics(
                    label: 'Close popup',
                    button: true,
                    child: GestureDetector(
                      onTap: onClose,
                      child: const Icon(Icons.close,
                          size: 18, color: Colors.grey),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_roomTypeLabel(room.type)}  ·  Floor ${floor.number}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F3FD),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.accessible_rounded,
                        size: 13, color: AppColors.info),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _roomAccessibility(room.type),
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF185FA5),
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Report dialog (extracted as a proper widget) ─────────────────────────────
class _ReportDialog extends StatefulWidget {
  final FloorData floor;
  final Future<void> Function(PWDReport) onSubmit;
  const _ReportDialog({required this.floor, required this.onSubmit});

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  late String _selectedLocation;
  String _selectedType = 'hazard';
  String _selectedSeverity = 'medium';
  bool _submitting = false;
  final _descCtrl = TextEditingController();

  static const _issueTypes = ['ramp', 'stairs', 'hazard', 'exit', 'noise'];
  static const _severities = ['low', 'medium', 'high'];
  static const _severityColors = {
    'low': (Color(0xFFDEF2E8), Color(0xFF27724A)),
    'medium': (Color(0xFFFFF0D8), Color(0xFF7A4A0A)),
    'high': (Color(0xFFFDE8E8), Color(0xFF8B1F1F)),
  };

  List<(String, double)> get _locations =>
      kFloorLocations[widget.floor.number] ?? [];

  @override
  void initState() {
    super.initState();
    _selectedLocation = _locations.isNotEmpty ? _locations.first.$1 : '';
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final loc = _locations.firstWhere(
      (l) => l.$1 == _selectedLocation,
      orElse: () => _locations.first,
    );
    final report = PWDReport(
      id: 'r${DateTime.now().millisecondsSinceEpoch}',
      floor: widget.floor.number,
      location: _selectedLocation,
      issueType: _selectedType,
      description: _descCtrl.text.trim().isEmpty
          ? '$_selectedType issue reported here'
          : _descCtrl.text.trim(),
      severity: _selectedSeverity,
      xNorm: loc.$2,
    );
    setState(() => _submitting = true);
    await widget.onSubmit(report);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.tealLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.add_location_alt_outlined,
                color: AppColors.teal, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Report on ${widget.floor.label}',
              style: const TextStyle(fontSize: 15)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            _label('Location'),
            const SizedBox(height: 5),
            DropdownButtonFormField<String>(
              initialValue: _selectedLocation,
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: _locations
                  .map((loc) => DropdownMenuItem<String>(
                        value: loc.$1,
                        child: Text(loc.$1,
                            style: const TextStyle(fontSize: 12)),
                      ))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _selectedLocation = v ?? _selectedLocation),
            ),
            const SizedBox(height: 14),
            _label('Issue type'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _issueTypes.map((t) {
                final active = _selectedType == t;
                return Semantics(
                  label: '$t issue type',
                  selected: active,
                  button: true,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedType = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFFE6F1FB)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active
                              ? AppColors.info
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        t,
                        style: TextStyle(
                          fontSize: 11,
                          color: active
                              ? const Color(0xFF185FA5)
                              : Colors.grey[600],
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            _label('Severity'),
            const SizedBox(height: 6),
            Row(
              children: _severities.map((s) {
                final active = _selectedSeverity == s;
                final colors = _severityColors[s]!;
                return Expanded(
                  child: Semantics(
                    label: '$s severity',
                    selected: active,
                    button: true,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedSeverity = s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: active ? colors.$1 : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: active ? colors.$2 : Colors.transparent,
                            width: active ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          s,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: active ? colors.$2 : Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            _label('Description'),
            const SizedBox(height: 5),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              maxLength: 200,
              decoration: InputDecoration(
                hintText: 'Briefly describe the issue...',
                hintStyle:
                    const TextStyle(fontSize: 12, color: Colors.grey),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
                counterStyle:
                    const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teal,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
      );
}

// ─── Disability active banner ─────────────────────────────────────────────────
class _DisabilityBanner extends StatelessWidget {
  final DisabilityMode mode;
  const _DisabilityBanner({required this.mode});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 10,
      left: 10,
      child: Semantics(
        label: '${mode.label} accessibility mode is active',
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.amber[100],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.amber.shade400, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(mode.icon, size: 12, color: Colors.amber[800]),
              const SizedBox(width: 5),
              Text(
                mode.label.toUpperCase(),
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber[800]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Disability picker ────────────────────────────────────────────────────────
class _DisabilityPicker extends StatelessWidget {
  final DisabilityMode current;
  final ValueChanged<DisabilityMode> onChanged;
  const _DisabilityPicker(
      {required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Set accessibility mode',
      child: PopupMenuButton<DisabilityMode>(
        icon: Icon(
          Icons.accessibility_new_rounded,
          color: current != DisabilityMode.none
              ? AppColors.teal
              : Colors.grey,
        ),
        onSelected: (d) =>
            onChanged(current == d ? DisabilityMode.none : d),
        itemBuilder: (_) => [
          const PopupMenuItem<DisabilityMode>(
            enabled: false,
            child: Text('Accessibility mode',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const PopupMenuDivider(),
          ...DisabilityMode.values.map(
            (d) => PopupMenuItem<DisabilityMode>(
              value: d,
              child: Row(
                children: [
                  Icon(d.icon,
                      size: 16,
                      color: current == d
                          ? AppColors.teal
                          : Colors.grey),
                  const SizedBox(width: 10),
                  Text(d.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: current == d
                            ? AppColors.teal
                            : null,
                        fontWeight: current == d
                            ? FontWeight.w600
                            : FontWeight.normal,
                      )),
                  if (current == d) ...[
                    const Spacer(),
                    const Icon(Icons.check,
                        size: 14, color: AppColors.teal),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Ranking bar ──────────────────────────────────────────────────────────────
class _RankingBar extends StatelessWidget {
  final int currentFloor;
  const _RankingBar({required this.currentFloor});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Accessibility rankings for all floors',
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(
          children: kFloors.map((f) {
            final active = f.number == currentFloor;
            final r = kFloorRanking[f.number]!;
            final score = r.$1.split(' ').last.replaceAll('(', '').replaceAll(')', '');
            return Expanded(
              child: Semantics(
                label: 'Floor ${f.number}: ${r.$1}',
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin:
                      const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: r.$3,
                    borderRadius: BorderRadius.circular(6),
                    border: active
                        ? Border.all(color: r.$2, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'F${f.number}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: r.$2,
                        ),
                      ),
                      Text(
                        score,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 8, color: r.$2),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─── Floor plan painter (unchanged, only minor additions) ─────────────────────
class FloorPlanPainter extends CustomPainter {
  final FloorData floor;
  final AppMode mode;
  final DisabilityMode disability;
  final List<PWDReport> reports;
  final PWDReport? selected;

  static const double corridorH = 35.0;
  static const double stairsW = 22.0;

  const FloorPlanPainter({
    required this.floor,
    required this.mode,
    required this.disability,
    required this.reports,
    this.selected,
  });

  bool get _hiContrast => disability == DisabilityMode.visual;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final roomH = h - corridorH;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..color =
            _hiContrast ? Colors.black : const Color(0xFFF4F4F2),
    );

    // Corridor
    canvas.drawRect(
      Rect.fromLTWH(0, roomH, w, corridorH),
      Paint()
        ..color =
            _hiContrast ? const Color(0xFF2A2A00) : const Color(0xFFE8E6E0),
    );
    canvas.drawLine(
      Offset(0, roomH),
      Offset(w, roomH),
      Paint()
        ..color = _hiContrast ? Colors.yellow : const Color(0xFFCCCAC4)
        ..strokeWidth = 0.8,
    );
    _text(canvas, 'CORRIDOR', w / 2, roomH + corridorH / 2,
        fs: 8,
        color: _hiContrast ? Colors.yellow : const Color(0xFF999999),
        maxW: w);

    // Rooms
    final roomStartX = floor.stairsLeft ? stairsW : 4.0;
    final roomEndX = floor.stairsRight ? w - stairsW : w - 4.0;
    final totalFactor = floor.rooms
        .fold(0.0, (double s, RoomData r) => s + r.widthFactor);
    final unitW = (roomEndX - roomStartX) / totalFactor;

    double x = roomStartX;
    for (final room in floor.rooms) {
      final rw = unitW * room.widthFactor;
      _drawRoom(canvas, Rect.fromLTWH(x + 1, 4, rw - 2, roomH - 8), room);
      x += rw;
    }

    if (floor.stairsLeft) {
      _drawStairs(canvas, Rect.fromLTWH(2, 4, stairsW - 4, roomH - 8));
    }
    if (floor.stairsRight) {
      _drawStairs(
          canvas, Rect.fromLTWH(w - stairsW + 2, 4, stairsW - 4, roomH - 8));
    }

    // Routes
    if (mode == AppMode.pwd) {
      final route = switch (disability) {
        DisabilityMode.visual => kVisualRoutes[floor.number],
        DisabilityMode.hearing => kHearingRoutes[floor.number],
        _ => kPwdRoutes[floor.number],
      };
      _drawRoute(canvas, w, roomH, route, AppColors.teal);
      if (floor.stairsLeft) {
        _drawAvoidX(canvas, stairsW / 2, roomH + corridorH / 2);
      }
      if (floor.stairsRight) {
        _drawAvoidX(canvas, w - stairsW / 2, roomH + corridorH / 2);
      }
    } else if (mode == AppMode.emergency) {
      _drawRoute(canvas, w, roomH, kEmergencyRoutes[floor.number], Colors.red);
    }

    // Border
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..color =
            _hiContrast ? Colors.white : const Color(0xFFAAAAAA)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // Markers
    for (final report in reports) {
      _drawMarker(
        canvas,
        Offset(report.xNorm * w, roomH / 2),
        report,
        selected?.id == report.id,
      );
    }
  }

  void _drawRoom(Canvas canvas, Rect rect, RoomData room) {
    final fill = _hiContrast
        ? Colors.black
        : switch (room.type) {
            RoomType.classroom => Colors.white,
            RoomType.lab => const Color(0xFFEFF4FE),
            RoomType.office => const Color(0xFFFFF9EE),
            RoomType.toilet => const Color(0xFFEBF8F2),
            RoomType.utility => const Color(0xFFF4F4F2),
          };

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()
        ..color = _hiContrast ? Colors.white : Colors.grey.shade300
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );

    _text(canvas, room.name, rect.center.dx, rect.center.dy,
        fs: 8,
        color: _hiContrast ? Colors.white : Colors.black87,
        maxW: rect.width - 4);

    if (room.badge != null) {
      const bR = 9.0;
      canvas.drawCircle(
        Offset(rect.right - bR - 2, rect.top + bR + 3),
        bR,
        Paint()
          ..color = _hiContrast
              ? Colors.white
              : const Color(0xFF1A1A2E),
      );
      _text(canvas, room.badge!, rect.right - bR - 2, rect.top + bR + 3,
          fs: 8,
          color: _hiContrast ? Colors.black : Colors.white,
          bold: true,
          maxW: bR * 2);
    }
  }

  void _drawStairs(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..color = _hiContrast
            ? const Color(0xFF222200)
            : const Color(0xFFDEDCDA),
    );
    for (int i = 1; i < 5; i++) {
      canvas.drawLine(
        Offset(rect.left, rect.top + (rect.height / 5) * i),
        Offset(rect.right, rect.top + (rect.height / 5) * i),
        Paint()
          ..color = _hiContrast ? Colors.yellow : Colors.black26
          ..strokeWidth = 0.7,
      );
    }
    final arrow = floor.number == 5 ? '▼' : '▲';
    _text(canvas, arrow, rect.center.dx, rect.center.dy,
        fs: 10,
        color: _hiContrast ? Colors.yellow : Colors.black38,
        maxW: rect.width);
  }

  void _drawAvoidX(Canvas canvas, double cx, double cy) {
    final p = Paint()
      ..color = AppColors.danger
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 7, cy - 7), Offset(cx + 7, cy + 7), p);
    canvas.drawLine(Offset(cx + 7, cy - 7), Offset(cx - 7, cy + 7), p);
    canvas.drawCircle(
      Offset(cx, cy),
      10,
      Paint()
        ..color = AppColors.danger
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawRoute(Canvas canvas, double w, double roomH,
      FloorRoute? route, Color color) {
    if (route == null) return;
    final cy = roomH + corridorH / 2;
    final sx = route.startX * w;
    final ex = route.endX * w;

    final src = Path()
      ..moveTo(sx, cy)
      ..lineTo(ex, cy);
    final dashed = Path();
    for (final m in src.computeMetrics()) {
      double d = 0;
      bool dr = true;
      while (d < m.length) {
        final l = dr ? 9.0 : 5.0;
        if (dr) dashed.addPath(m.extractPath(d, d + l), Offset.zero);
        d += l;
        dr = !dr;
      }
    }
    canvas.drawPath(
      dashed,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    final dir = ex > sx ? 1.0 : -1.0;
    canvas.drawPath(
      Path()
        ..moveTo(ex + dir * 11, cy)
        ..lineTo(ex, cy - 6)
        ..lineTo(ex, cy + 6)
        ..close(),
      Paint()..color = color,
    );
    canvas.drawCircle(Offset(sx, cy), 5, Paint()..color = color);
  }

  void _drawMarker(
      Canvas canvas, Offset center, PWDReport report, bool isSelected) {
    final c = report.issueColor;
    final r = isSelected ? 12.0 : 9.0;
    if (isSelected) {
      canvas.drawCircle(center, r + 5, Paint()..color = c.withOpacity(0.22));
    }
    canvas.drawCircle(center, r, Paint()..color = c);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    _text(
      canvas,
      report.issueType == 'hazard'
          ? '!'
          : report.issueType[0].toUpperCase(),
      center.dx,
      center.dy,
      fs: isSelected ? 9 : 7,
      color: Colors.white,
      bold: true,
      maxW: r * 2,
    );
  }

  void _text(
    Canvas canvas,
    String t,
    double cx,
    double cy, {
    required double fs,
    required Color color,
    bool bold = false,
    required double maxW,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(
          fontSize: fs,
          color: color,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          height: 1.2,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW.clamp(1.0, double.infinity));
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant FloorPlanPainter old) =>
      old.floor != floor ||
      old.mode != mode ||
      old.disability != disability ||
      old.selected?.id != selected?.id ||
      old.reports.length != reports.length;
}