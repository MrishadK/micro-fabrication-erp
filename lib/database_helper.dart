import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:excel/excel.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  static const String _dbName = 'fab_shop_pro.db';
  // Version 14: added locked_daily_wage to worker_attendance
  static const int _dbVersion = 14;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(_dbName);
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
      return await openDatabase(
        fileName,
        version: _dbVersion,
        onCreate: _createDB,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure,
      );
    }
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationDocumentsDirectory();
    final dbFolder = Directory(join(dir.path, 'FabManager'));
    if (!await dbFolder.exists()) await dbFolder.create(recursive: true);

    return await openDatabase(
      join(dbFolder.path, fileName),
      version: _dbVersion,
      onConfigure: _onConfigure,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  Future _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future _createDB(Database db, int version) async {
    // --- JOBS TABLE (Now explicitly storing deductions) ---
    await db.execute('''
      CREATE TABLE jobs (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        bill_no TEXT, client_name TEXT, client_place TEXT, client_phone TEXT, 
        material_brought TEXT, qty_given INTEGER, product_type TEXT, 
        target_qty INTEGER, items TEXT, work_details TEXT, total_cost REAL, 
        discount REAL DEFAULT 0.0, 
        scrap_value REAL DEFAULT 0.0, 
        advance_paid REAL DEFAULT 0.0,
        created_at TEXT, deadline_date TEXT, completed_at TEXT, status TEXT
      )
    ''');

    // --- DELIVERIES TABLE ---
    await db.execute('''
      CREATE TABLE deliveries (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        job_id INTEGER, item_name TEXT, qty_delivered INTEGER, delivery_date TEXT, 
        FOREIGN KEY(job_id) REFERENCES jobs(id) ON DELETE CASCADE
      )
    ''');

    // --- CLIENT PAYMENTS TABLE ---
    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        job_id INTEGER, amount REAL, payment_date TEXT, notes TEXT, 
        FOREIGN KEY(job_id) REFERENCES jobs(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE TABLE drafts (key TEXT PRIMARY KEY, value TEXT)');

    // --- WORKER TABLES ---
    await _createWorkerTables(db);
  }

  Future _createWorkerTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        rate REAL,
        wage_type TEXT DEFAULT 'daily',
        ot_type TEXT,
        ot_val REAL,
        piece_items TEXT DEFAULT '[]',
        employee_phone TEXT DEFAULT '',
        status TEXT DEFAULT 'Active',
        employee_number INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS worker_attendance (
        worker_id INTEGER,
        date TEXT,
        overtime_hours REAL DEFAULT 0.0,
        work_fraction REAL DEFAULT 1.0,
        pieces REAL DEFAULT 0.0,
        tasks TEXT DEFAULT '[]', 
        locked_daily_wage REAL DEFAULT 0.0,
        PRIMARY KEY (worker_id, date),
        FOREIGN KEY(worker_id) REFERENCES workers(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS worker_payments (
        worker_id INTEGER,
        week_start_date TEXT,
        amount REAL,
        paid_date TEXT,
        PRIMARY KEY (worker_id, week_start_date),
        FOREIGN KEY(worker_id) REFERENCES workers(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS worker_payment_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        worker_id INTEGER,
        week_start_date TEXT,
        amount REAL,
        paid_date TEXT,
        FOREIGN KEY(worker_id) REFERENCES workers(id) ON DELETE CASCADE
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute("ALTER TABLE jobs ADD COLUMN bill_no TEXT");
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute("ALTER TABLE deliveries ADD COLUMN item_name TEXT");
      } catch (_) {}
    }
    if (oldVersion < 4) {
      await _createWorkerTables(db);
    }
    if (oldVersion < 5) {
      try {
        await db.execute(
          "ALTER TABLE worker_attendance ADD COLUMN work_fraction REAL DEFAULT 1.0",
        );
      } catch (_) {}
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS worker_payments (
          worker_id INTEGER,
          week_start_date TEXT,
          amount REAL,
          paid_date TEXT,
          PRIMARY KEY (worker_id, week_start_date),
          FOREIGN KEY(worker_id) REFERENCES workers(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 7) {
      try {
        await db.execute(
          "ALTER TABLE workers ADD COLUMN wage_type TEXT DEFAULT 'daily'",
        );
        await db.execute(
          "ALTER TABLE worker_attendance ADD COLUMN pieces REAL DEFAULT 0.0",
        );
      } catch (_) {}
    }
    if (oldVersion < 8) {
      try {
        await db.execute(
          "ALTER TABLE worker_attendance ADD COLUMN tasks TEXT DEFAULT '[]'",
        );
      } catch (_) {}
    }
    if (oldVersion < 9) {
      try {
        await db.execute(
          "ALTER TABLE workers ADD COLUMN piece_items TEXT DEFAULT '[]'",
        );
      } catch (_) {}
    }
    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS worker_payment_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          worker_id INTEGER,
          week_start_date TEXT,
          amount REAL,
          paid_date TEXT,
          FOREIGN KEY(worker_id) REFERENCES workers(id) ON DELETE CASCADE
        )
      ''');
      try {
        await db.execute('''
          INSERT INTO worker_payment_history (worker_id, week_start_date, amount, paid_date)
          SELECT worker_id, week_start_date, amount, paid_date FROM worker_payments
        ''');
      } catch (_) {}
    }
    // Version 11 Migration: Add the missing financial deduction columns
    if (oldVersion < 11) {
      try {
        await db.execute(
          "ALTER TABLE jobs ADD COLUMN discount REAL DEFAULT 0.0",
        );
        await db.execute(
          "ALTER TABLE jobs ADD COLUMN scrap_value REAL DEFAULT 0.0",
        );
        await db.execute(
          "ALTER TABLE jobs ADD COLUMN advance_paid REAL DEFAULT 0.0",
        );
      } catch (_) {}
    }
    // Version 12 Migration: Add employee_phone and status to workers
    if (oldVersion < 12) {
      try {
        await db.execute(
          "ALTER TABLE workers ADD COLUMN employee_phone TEXT DEFAULT ''",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE workers ADD COLUMN status TEXT DEFAULT 'Active'",
        );
      } catch (_) {}
    }
    // Version 13 Migration: Add employee_number to workers and backfill existing
    if (oldVersion < 13) {
      try {
        await db.execute(
          "ALTER TABLE workers ADD COLUMN employee_number INTEGER",
        );
        // Backfill existing records
        final List<Map<String, dynamic>> existingWorkers = await db.query(
          'workers',
          orderBy: 'id ASC',
        );
        int currentNumber = 1;
        for (final worker in existingWorkers) {
          await db.update(
            'workers',
            {'employee_number': currentNumber},
            where: 'id = ?',
            whereArgs: [worker['id']],
          );
          currentNumber++;
        }
      } catch (e) {
        debugPrint("Version 13 Migration Error: $e");
      }
    }
    // Version 14 Migration: Add locked_daily_wage and backfill it
    if (oldVersion < 14) {
      try {
        await db.execute(
          "ALTER TABLE worker_attendance ADD COLUMN locked_daily_wage REAL DEFAULT 0.0",
        );
        await db.execute('''
          UPDATE worker_attendance 
          SET locked_daily_wage = (SELECT rate FROM workers WHERE workers.id = worker_attendance.worker_id)
        ''');
      } catch (e) {
        debugPrint("Version 14 Migration Error: $e");
      }
    }
  }

  // ====================================================
  //               WORKER MANAGEMENT LOGIC
  // ====================================================

  Future<int> getMaxEmployeeNumber() async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT MAX(employee_number) as max_num FROM workers',
    );
    if (result.isNotEmpty && result.first['max_num'] != null) {
      return (result.first['max_num'] as num).toInt();
    }
    return 0;
  }

  Future<int> saveWorker(Map<String, dynamic> worker) async {
    final db = await instance.database;
    String pieceItemsJson = jsonEncode(worker['piece_items'] ?? []);

    if (worker['id'] != null && worker['id'] is int) {
      final Map<String, dynamic> updateData = {
        'name': worker['name'],
        'rate': worker['rate'],
        'wage_type': worker['wage_type'] ?? 'daily',
        'ot_type': worker['ot_type'],
        'ot_val': worker['ot_val'],
        'piece_items': pieceItemsJson,
        'employee_phone': worker['employee_phone'] ?? '',
        'status': worker['status'] ?? 'Active',
      };
      if (worker.containsKey('employee_number')) {
        updateData['employee_number'] = worker['employee_number'];
      }
      await db.update(
        'workers',
        updateData,
        where: 'id = ?',
        whereArgs: [worker['id']],
      );
      return worker['id'];
    } else {
      // For new workers, ensure they have an employee_number
      int newEmpNum =
          worker['employee_number'] ?? ((await getMaxEmployeeNumber()) + 1);
      return await db.insert('workers', {
        'name': worker['name'],
        'rate': worker['rate'],
        'wage_type': worker['wage_type'] ?? 'daily',
        'ot_type': worker['ot_type'],
        'ot_val': worker['ot_val'],
        'piece_items': pieceItemsJson,
        'employee_phone': worker['employee_phone'] ?? '',
        'status': worker['status'] ?? 'Active',
        'employee_number': newEmpNum,
      });
    }
  }

  Future<void> deleteWorker(int id) async {
    final db = await instance.database;
    await db.delete('workers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateWorkerAttendance(
    int workerId,
    List<Map<String, dynamic>> attendanceData,
  ) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'worker_attendance',
        where: 'worker_id = ?',
        whereArgs: [workerId],
      );
      final batch = txn.batch();

      for (var entry in attendanceData) {
        batch.insert('worker_attendance', {
          'worker_id': workerId,
          'date': entry['date'],
          'work_fraction': entry['fraction'] ?? 1.0,
          'overtime_hours': entry['ot'] ?? 0.0,
          'pieces': entry['pieces'] ?? 0.0,
          'tasks': jsonEncode(entry['tasks'] ?? []),
          'locked_daily_wage': entry['locked_daily_wage'] ?? 0.0,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getWorkersWithAttendance() async {
    final db = await instance.database;
    final workers = await db.query('workers');
    if (workers.isEmpty) return [];

    List<Map<String, dynamic>> result = [];
    for (var w in workers) {
      int id = w['id'] as int;
      final attRows = await db.query(
        'worker_attendance',
        where: 'worker_id = ?',
        whereArgs: [id],
      );

      Map<String, dynamic> attendanceMap = {};

      for (var row in attRows) {
        String date = row['date'] as String;
        double ot = (row['overtime_hours'] as num?)?.toDouble() ?? 0.0;
        double frac = (row['work_fraction'] as num?)?.toDouble() ?? 1.0;
        double pieces = (row['pieces'] as num?)?.toDouble() ?? 0.0;
        double lockedWage =
            (row['locked_daily_wage'] as num?)?.toDouble() ?? 0.0;
        List<dynamic> tasksList = [];
        try {
          if (row['tasks'] != null) {
            tasksList = jsonDecode(row['tasks'] as String);
          }
        } catch (_) {}

        attendanceMap[date] = {
          'fraction': frac,
          'ot': ot,
          'pieces': pieces,
          'tasks': tasksList,
          'locked_daily_wage': lockedWage,
        };
      }

      List<dynamic> pItems = [];
      try {
        if (w['piece_items'] != null) {
          pItems = jsonDecode(w['piece_items'] as String);
        }
      } catch (_) {}

      result.add({
        'id': id,
        'name': w['name'],
        'rate': w['rate'],
        'wage_type': w['wage_type'] ?? 'daily',
        'ot_type': w['ot_type'],
        'ot_val': w['ot_val'],
        'piece_items': pItems,
        'employee_phone': w['employee_phone'] ?? '',
        'status': w['status'] ?? 'Active',
        'employee_number':
            w['employee_number'], // include so UI can show/lock it
        'attendance_data': attendanceMap,
      });
    }
    return result;
  }

  // --- WEEKLY PAYMENTS LEDGER ---

  Future<void> markWeeklyPayment(
    int workerId,
    String weekStart,
    double amount, {
    String? paidDate,
  }) async {
    final db = await instance.database;
    await db.insert('worker_payment_history', {
      'worker_id': workerId,
      'week_start_date': weekStart,
      'amount': amount,
      'paid_date': paidDate ?? DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteSinglePayment(int paymentId) async {
    final db = await instance.database;
    await db.delete(
      'worker_payment_history',
      where: 'id = ?',
      whereArgs: [paymentId],
    );
  }

  Future<void> unmarkWeeklyPayment(int workerId, String weekStart) async {
    final db = await instance.database;
    await db.delete(
      'worker_payment_history',
      where: 'worker_id = ? AND week_start_date = ?',
      whereArgs: [workerId, weekStart],
    );
  }

  Future<Map<int, List<Map<String, dynamic>>>> getWeeklyPaymentStatus(
    String weekStart,
  ) async {
    final db = await instance.database;
    final res = await db.query(
      'worker_payment_history',
      where: 'week_start_date = ?',
      whereArgs: [weekStart],
      orderBy: 'paid_date ASC',
    );

    Map<int, List<Map<String, dynamic>>> map = {};
    for (var row in res) {
      int wId = row['worker_id'] as int;
      if (!map.containsKey(wId)) map[wId] = [];
      map[wId]!.add(row);
    }
    return map;
  }

  // ====================================================
  //                 JOB MANAGEMENT LOGIC
  // ====================================================

  Future<String> generateNextBillNumber() async {
    final db = await instance.database;
    final result = await db.rawQuery(
      "SELECT MAX(CAST(bill_no AS INTEGER)) as max_val FROM jobs",
    );
    int maxBill = 0;
    if (result.isNotEmpty) {
      maxBill = (result.first['max_val'] as int?) ?? 0;
    }
    return (maxBill + 1).toString();
  }

  Future<void> addDelivery(
    int jobId,
    String itemName,
    int qty, {
    String? date,
  }) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.insert('deliveries', {
        'job_id': jobId,
        'item_name': itemName,
        'qty_delivered': qty,
        'delivery_date': date ?? DateTime.now().toIso8601String(),
      });
      await _checkJobCompletion(txn, jobId);
    });
  }

  Future<List<Map<String, dynamic>>> getJobDeliveries(int jobId) async {
    final db = await instance.database;
    return await db.query(
      'deliveries',
      where: 'job_id = ?',
      whereArgs: [jobId],
      orderBy: 'delivery_date DESC',
    );
  }

  Future<void> updateDeliveryDate(int deliveryId, String newDate) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.update(
        'deliveries',
        {'delivery_date': newDate},
        where: 'id = ?',
        whereArgs: [deliveryId],
      );
      final delRes = await txn.query(
        'deliveries',
        columns: ['job_id'],
        where: 'id = ?',
        whereArgs: [deliveryId],
      );
      if (delRes.isNotEmpty) {
        int jobId = delRes.first['job_id'] as int;
        await _checkJobCompletion(txn, jobId);
      }
    });
  }

  Future<void> deleteDelivery(int deliveryId) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final delRes = await txn.query(
        'deliveries',
        columns: ['job_id'],
        where: 'id = ?',
        whereArgs: [deliveryId],
      );
      await txn.delete('deliveries', where: 'id = ?', whereArgs: [deliveryId]);
      if (delRes.isNotEmpty) {
        int jobId = delRes.first['job_id'] as int;
        await _checkJobCompletion(txn, jobId);
      }
    });
  }

  Future<Map<String, int>> getItemDeliveryStats(int jobId) async {
    final db = await instance.database;
    final res = await db.rawQuery(
      "SELECT COALESCE(item_name, 'Unknown') as item_name, SUM(qty_delivered) as total FROM deliveries WHERE job_id = ? GROUP BY item_name",
      [jobId],
    );
    Map<String, int> stats = {};
    for (var row in res) {
      stats[row['item_name'] as String] = (row['total'] as int);
    }
    return stats;
  }

  Future<void> _checkJobCompletion(Transaction txn, int jobId) async {
    final jobRes = await txn.query(
      'jobs',
      columns: ['items'],
      where: 'id = ?',
      whereArgs: [jobId],
    );
    if (jobRes.isEmpty) return;
    try {
      final json = jsonDecode(jobRes.first['items'] as String);
      List<dynamic> outList = json['out'] ?? [];
      if (outList.isEmpty) return;
      final delRes = await txn.rawQuery(
        "SELECT COALESCE(item_name, 'Unknown') as item_name, SUM(qty_delivered) as total FROM deliveries WHERE job_id = ? GROUP BY item_name",
        [jobId],
      );
      Map<String, int> deliveredMap = {};
      for (var row in delRes) {
        deliveredMap[row['item_name'] as String] = (row['total'] as int);
      }
      bool allDone = true;
      for (var item in outList) {
        if ((deliveredMap[item['name']] ?? 0) < item['qty']) {
          allDone = false;
          break;
        }
      }

      String? completedDate;
      if (allDone) {
        final maxDelRes = await txn.rawQuery(
          "SELECT MAX(delivery_date) as max_date FROM deliveries WHERE job_id = ?",
          [jobId],
        );
        if (maxDelRes.isNotEmpty && maxDelRes.first['max_date'] != null) {
          completedDate = maxDelRes.first['max_date'] as String;
        } else {
          completedDate = DateTime.now().toIso8601String();
        }
      }

      await txn.update(
        'jobs',
        {'status': allDone ? 'Done' : 'Ongoing', 'completed_at': completedDate},
        where: 'id = ?',
        whereArgs: [jobId],
      );
    } catch (_) {}
  }

  Future<int> createJob(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('jobs', row);
  }

  Future<int> updateJob(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.update(
      'jobs',
      row,
      where: 'id = ?',
      whereArgs: [row['id']],
    );
  }

  Future<int> deleteJob(int id) async {
    final db = await instance.database;
    return await db.transaction((txn) async {
      await txn.delete('deliveries', where: 'job_id = ?', whereArgs: [id]);
      await txn.delete('payments', where: 'job_id = ?', whereArgs: [id]);
      return await txn.delete('jobs', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> updateStatus(int id, String s) async {
    final db = await instance.database;
    await db.update(
      'jobs',
      {
        'status': s,
        'completed_at': s == 'Done' ? DateTime.now().toIso8601String() : null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getActiveJobs() async {
    final db = await instance.database;
    return await db.rawQuery(
      "SELECT j.*, COALESCE(SUM(d.qty_delivered), 0) as delivered_sum, (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE job_id = j.id) as paid_sum FROM jobs j LEFT JOIN deliveries d ON j.id = d.job_id GROUP BY j.id ORDER BY j.created_at ASC",
    );
  }

  Future<List<Map<String, dynamic>>> getHistoryJobs(String query) async {
    final db = await instance.database;
    String sql =
        "SELECT j.*, (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE job_id = j.id) as paid_sum FROM jobs j WHERE j.status = 'Done'";
    List<Object?> args = [];
    if (query.isNotEmpty) {
      sql +=
          " AND (j.bill_no LIKE ? OR j.client_name LIKE ?)";
      args.addAll(['%$query%', '%$query%']);
    }
    sql += " ORDER BY j.completed_at DESC";
    return await db.rawQuery(sql, args);
  }

  Future<List<Map<String, dynamic>>> getClientHistory(String query) async {
    final db = await instance.database;
    if (query.isEmpty) return [];
    return await db.rawQuery(
      "SELECT j.*, (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE job_id = j.id) as paid_sum FROM jobs j WHERE j.client_name LIKE ? OR j.client_phone LIKE ? ORDER BY j.created_at DESC",
      ['$query%', '$query%'],
    );
  }

  Future<List<Map<String, dynamic>>> getClientUnpaidBills(
    String clientName, 
    int excludeJobId,
  ) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT j.*, 
             (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE job_id = j.id) as paid_sum
      FROM jobs j
      WHERE j.client_name = ? 
        AND j.id != ?
        AND j.total_cost > 0
      ORDER BY j.created_at DESC
    ''', [clientName, excludeJobId]);
  }

  Future<List<Map<String, dynamic>>> getTopDebtors() async {
    final db = await instance.database;
    // Modified to subtract discount and scrap from total_cost before checking if they are a debtor.
    final result = await db.rawQuery(
      "SELECT j.client_name, j.client_phone, COUNT(j.id) as job_count, SUM(j.total_cost - COALESCE(j.discount, 0) - COALESCE(j.scrap_value, 0)) as total_bill, SUM((SELECT COALESCE(SUM(amount), 0) FROM payments WHERE job_id = j.id) + COALESCE(j.advance_paid, 0)) as total_paid FROM jobs j GROUP BY j.client_name, j.client_phone ORDER BY (total_bill - total_paid) DESC LIMIT 50",
    );
    return result
        .where(
          (row) =>
              ((row['total_bill'] as num?)?.toDouble() ?? 0) -
                  ((row['total_paid'] as num?)?.toDouble() ?? 0) >
              1.0,
        )
        .toList();
  }

  Future<void> addPayment(
    int jobId,
    double amount,
    String note, {
    String? date,
  }) async {
    final db = await instance.database;
    final paymentDate = date ?? DateTime.now().toIso8601String();

    await db.insert('payments', {
      'job_id': jobId,
      'amount': amount,
      'notes': note,
      'payment_date': paymentDate,
    });
  }

  Future<List<Map<String, dynamic>>> getJobPayments(int jobId) async {
    final db = await instance.database;
    return await db.query('payments', where: 'job_id = ?', whereArgs: [jobId]);
  }

  Future<int> importFromExcel(List<int> bytes) async {
    final db = await instance.database;
    var excel = Excel.decodeBytes(bytes);
    int importedCount = 0;
    for (var table in excel.tables.keys) {
      var rows = excel.tables[table]!.rows;
      if (rows.isEmpty) continue;
      Map<String, int> headerMap = {};
      var headerRow = rows.first;
      for (int i = 0; i < headerRow.length; i++) {
        final String val = headerRow[i]?.value.toString().toLowerCase().trim() ?? "";
        if (val.isEmpty) continue;

        if ((val.contains("date") || val.contains("booking") || val.contains("entry")) && 
            !val.contains("delivered") && !val.contains("completed") && !val.contains("finish")) {
          headerMap['created_at'] = i;
        } else if (val.contains("bill") || val.contains("invoice") || val.contains("p no") || val == "bill_no" || val == "billno") {
          headerMap['bill_no'] = i;
        } else if (val.contains("client") || val.contains("customer") || val == "name" || val.contains("client_name") || val.contains("customer_name")) {
          headerMap['client_name'] = i;
        } else if (val.contains("place") || val.contains("location") || val.contains("address") || val.contains("city") || val.contains("area")) {
          headerMap['client_place'] = i;
        } else if (val.contains("phone") || val.contains("mobile") || val.contains("contact") || val.contains("tel") || val.contains("telephone")) {
          headerMap['client_phone'] = i;
        } else if (val.contains("material") || val.contains("item") || val.contains("input") || val.contains("incoming")) {
          headerMap['material_brought'] = i;
        } else if (val.contains("qty") || val.contains("quantity") || val.contains("pcs") || val.contains("pieces") || 
            (val.contains("total") && !val.contains("cost") && !val.contains("bill") && !val.contains("days"))) {
          headerMap['qty_given'] = i;
        } else if (val.contains("product") || val.contains("output") || val.contains("workdetails") || val.contains("work details") || 
            val.contains("description") || val.contains("job details")) {
          headerMap['product_type'] = i;
        } else if (val.contains("status") || val == "state") {
          headerMap['status'] = i;
        } else if (val.contains("delivered") || val.contains("delivery") || val.contains("completed_at") || val.contains("finish date") || val.contains("completed date")) {
          headerMap['completed_at'] = i;
        } else if (val.contains("cost") || val.contains("amount") || val.contains("price") || val.contains("rate") || val == "total") {
          headerMap['total_cost'] = i;
        } else if (val.contains("advance") || val.contains("paid")) {
          headerMap['advance_paid'] = i;
        }
      }
      for (int i = 1; i < rows.length; i++) {
        var row = rows[i];
        if (row.isEmpty) continue;
        dynamic getVal(String key) =>
            headerMap.containsKey(key) && headerMap[key]! < row.length
            ? row[headerMap[key]!]?.value
            : null;

        String parseDate(dynamic rawDate) {
          if (rawDate == null) return DateTime.now().toIso8601String();
          try {
            if (rawDate is DateTime) return rawDate.toIso8601String();
            if (rawDate is int)
              return DateTime(
                1900,
                1,
                1,
              ).add(Duration(days: rawDate - 2)).toIso8601String();
            String s = rawDate.toString().replaceAll('/', '-');
            List<String> parts = s.split('-');
            if (parts.length == 3 && int.parse(parts[0]) <= 31)
              return DateTime(
                int.parse(parts[2]),
                int.parse(parts[1]),
                int.parse(parts[0]),
              ).toIso8601String();
            return DateTime.parse(s).toIso8601String();
          } catch (e) {
            return DateTime.now().toIso8601String();
          }
        }

        String clientName = getVal('client_name')?.toString() ?? "";
        if (clientName.isEmpty) continue;

        String materialName = getVal('material_brought')?.toString() ?? "";
        int qtyGiven =
            int.tryParse(getVal('qty_given')?.toString() ?? "0") ?? 0;
        String productName = getVal('product_type')?.toString() ?? "";

        // Default product qty to qtyGiven so it makes sense in the job order details
        String itemsJson = jsonEncode({
          "in": materialName.isNotEmpty
              ? [
                  {
                    "id": "mat_${DateTime.now().microsecondsSinceEpoch}",
                    "name": materialName,
                    "qty": qtyGiven,
                  },
                ]
              : [],
          "out": productName.isNotEmpty
              ? [
                  {
                    "id": "prod_${DateTime.now().microsecondsSinceEpoch}",
                    "name": productName,
                    "qty": qtyGiven,
                    "linked_ids": [],
                  },
                ]
              : [],
        });

        String rawStatus = getVal('status')?.toString().toLowerCase() ?? "";
        String finalStatus = "Ongoing";
        String? completedAt;
        var rawCompleted = getVal('completed_at');
        if (rawCompleted != null ||
            rawStatus.contains('done') ||
            rawStatus.contains('paid')) {
          finalStatus = "Done";
          completedAt = parseDate(rawCompleted ?? getVal('created_at'));
        }

        double totalCost = 0.0;
        if (headerMap.containsKey('total_cost')) {
          final val = getVal('total_cost')?.toString() ?? "0";
          final cleaned = val.replaceAll(RegExp(r'[^\d.]'), '');
          totalCost = double.tryParse(cleaned) ?? 0.0;
        }

        double advancePaid = 0.0;
        if (headerMap.containsKey('advance_paid')) {
          final val = getVal('advance_paid')?.toString() ?? "0";
          final cleaned = val.replaceAll(RegExp(r'[^\d.]'), '');
          advancePaid = double.tryParse(cleaned) ?? 0.0;
        }

        final int jobId = await db.insert('jobs', {
          'created_at': parseDate(getVal('created_at')),
          'bill_no': getVal('bill_no')?.toString() ?? "",
          'client_name': clientName,
          'client_place': getVal('client_place')?.toString() ?? "",
          'client_phone': getVal('client_phone')?.toString() ?? "",
          'material_brought': materialName,
          'qty_given': qtyGiven,
          'product_type': productName,
          'target_qty': qtyGiven, // Use qtyGiven as target output qty by default
          'items': itemsJson,
          'work_details': "",
          'total_cost': totalCost,
          'discount': 0.0,
          'scrap_value': 0.0,
          'advance_paid': advancePaid,
          'status': finalStatus,
          'completed_at': completedAt,
        });

        if (advancePaid > 0) {
          await db.insert('payments', {
            'job_id': jobId,
            'amount': advancePaid,
            'notes': 'Advance (Imported)',
            'payment_date': parseDate(getVal('created_at')),
          });
        }
        importedCount++;
      }
    }
    return importedCount;
  }

  Future<List<String>> getAllItemNames() async {
    final db = await instance.database;
    final result = await db.query('jobs', columns: ['items']);
    final Set<String> names = {};
    for (var row in result) {
      if (row['items'] == null) continue;
      try {
        final data = jsonDecode(row['items'] as String);
        for (var list in [data['in'], data['out']]) {
          if (list is List) {
            for (var i in list) {
              if (i['name']?.toString().isNotEmpty == true)
                names.add(i['name'].toString());
            }
          }
        }
      } catch (e) {}
    }
    final list = names.toList();
    list.sort();
    return list;
  }

  Future<List<Map<String, Object?>>> searchClients(String q) async {
    final db = await instance.database;
    return await db.rawQuery(
      "SELECT DISTINCT client_name, client_phone, client_place FROM jobs WHERE client_name LIKE ? LIMIT 5",
      ['$q%'],
    );
  }

  // --- SAFE EDIT FUNCTIONS ---
  Future<int> updatePaymentRecord(
    int paymentId,
    double newAmount,
    String newDate,
  ) async {
    final db = await instance.database;
    return await db.update(
      'payments',
      {'amount': newAmount, 'payment_date': newDate},
      where: 'id = ?',
      whereArgs: [paymentId],
    );
  }

  Future<int> updateBillDetails(
    int jobId,
    String orderDate,
    String? deliveryDate,
    String workDetails,
  ) async {
    final db = await instance.database;
    return await db.update(
      'jobs',
      {
        'created_at': orderDate,
        'completed_at': deliveryDate,
        'work_details': workDetails,
      },
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  Future<int> updateJobScrap(int jobId, double scrapValue) async {
    final db = await instance.database;
    return await db.update(
      'jobs',
      {'scrap_value': scrapValue},
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  Future<int> updateJobAdvance(int jobId, double advancePaid) async {
    final db = await instance.database;
    return await db.update(
      'jobs',
      {'advance_paid': advancePaid},
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  Future<String> getPublicDataPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return join(dir.path, 'FabManager');
  }

  Future<Map<String, dynamic>?> getJobByBillNo(String billNo) async {
    final db = await instance.database;
    final result = await db.query(
      'jobs',
      where: 'bill_no = ?',
      whereArgs: [billNo],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<List<Map<String, dynamic>>> getWorkersForJob(String billNo) async {
    final db = await instance.database;
    final query = '''
      SELECT w.name as worker_name, a.date, a.tasks
      FROM worker_attendance a
      JOIN workers w ON a.worker_id = w.id
      WHERE a.tasks != '[]' AND a.tasks IS NOT NULL
    ''';
    final results = await db.rawQuery(query);

    List<Map<String, dynamic>> linkedWork = [];

    for (var row in results) {
      try {
        final tasks = jsonDecode(row['tasks'] as String) as List;
        for (var task in tasks) {
          if (task['page_no']?.toString().trim() == billNo.trim()) {
            linkedWork.add({
              'worker_name': row['worker_name'],
              'date': row['date'],
              'task_name': task['name'],
              'qty': task['qty'],
              'rate': task['rate'],
              'total': task['total'],
            });
          }
        }
      } catch (e) {
        debugPrint('Error parsing task JSON: $e');
      }
    }

    linkedWork.sort((a, b) => b['date'].compareTo(a['date']));
    return linkedWork;
  }
}
