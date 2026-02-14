class Prescription {
  final String id;
  final String doctorId;
  final String patientId;
  final String medicineId;
  final String? notes;
  final String? exercise;
  final String createdAt;
  final String updatedAt;
  final Patient patient;
  final Medicine medicine;
  final List<Timing> timings;

  Prescription({
    required this.id,
    required this.doctorId,
    required this.patientId,
    required this.medicineId,
    this.notes,
    this.exercise,
    required this.createdAt,
    required this.updatedAt,
    required this.patient,
    required this.medicine,
    required this.timings,
  });

  factory Prescription.fromJson(Map<String, dynamic> json) {
    return Prescription(
      id: json['id'],
      doctorId: json['doctorId'],
      patientId: json['patientId'],
      medicineId: json['medicineId'],
      notes: json['notes'],
      exercise: json['exercise'],
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
      patient: Patient.fromJson(json['patient']),
      medicine: Medicine.fromJson(json['medicine']),
      timings: (json['timings'] as List)
          .map((e) => Timing.fromJson(e))
          .toList(),
    );
  }
}

class Patient {
  final String id;
  final String name;

  Patient({required this.id, required this.name});

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id'],
      name: json['name'],
    );
  }
}

class Medicine {
  final String id;
  final String name;
  final String dosage;
  final String type;
  final String manufacturer;

  Medicine({
    required this.id,
    required this.name,
    required this.dosage,
    required this.type,
    required this.manufacturer,
  });

  factory Medicine.fromJson(Map<String, dynamic> json) {
    return Medicine(
      id: json['id'],
      name: json['name'],
      dosage: json['dosage'],
      type: json['type'],
      manufacturer: json['manufacturer'],
    );
  }
}

class Timing {
  final String id;
  final String timingType;
  final String? customTime;

  Timing({
    required this.id,
    required this.timingType,
    this.customTime,
  });

  factory Timing.fromJson(Map<String, dynamic> json) {
    return Timing(
      id: json['id'],
      timingType: json['timingType'],
      customTime: json['customTime'],
    );
  }
}
