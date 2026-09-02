import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/services/location_service.dart';
import 'package:metro_shift_roster/features/stations/data/station_model.dart';
import 'package:metro_shift_roster/features/stations/presentation/station_provider.dart';

class CreateEditStationScreen extends ConsumerStatefulWidget {
  final StationModel? station;
  const CreateEditStationScreen({super.key, this.station});

  @override
  ConsumerState<CreateEditStationScreen> createState() =>
      _CreateEditStationScreenState();
}

class _CreateEditStationScreenState
    extends ConsumerState<CreateEditStationScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _latController;
  late final TextEditingController _lngController;
  late final TextEditingController _radiusController;
  late final TextEditingController _amountController;
  final _customTomController = TextEditingController();

  final _newShiftNameController = TextEditingController(text: 'A Shift');
  TimeOfDay _newShiftStart = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _newShiftEnd = const TimeOfDay(hour: 14, minute: 0);

  final List<String> _tomSystems = [];
  final List<Map<String, String>> _shiftTemplates = [];
  bool _isFetchingLocation = false;

  @override
  void initState() {
    super.initState();
    final stn = widget.station;
    _nameController = TextEditingController(text: stn?.name ?? '');
    _latController =
        TextEditingController(text: stn != null ? stn.latitude.toString() : '');
    _lngController = TextEditingController(
        text: stn != null ? stn.longitude.toString() : '');
    _radiusController = TextEditingController(
        text: stn != null ? stn.punchRadiusMeters.toString() : '600');
    _amountController = TextEditingController(
        text: stn != null ? stn.defaultFixedAmount.toString() : '700');

    if (stn != null) {
      _tomSystems.addAll(stn.operatingSystems.map((e) => e.systemName));
      _shiftTemplates.addAll(stn.shiftTemplates.map((e) => {
            'name': e.shiftName,
            'start': e.startTime,
            'end': e.endTime,
          }));
    } else {
      _tomSystems.addAll(['TOM 01', 'TOM 02']);
      _shiftTemplates.addAll([
        {'name': 'A Shift', 'start': '06:00:00', 'end': '14:00:00'},
        {'name': 'B Shift', 'start': '14:00:00', 'end': '22:00:00'},
      ]);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    _amountController.dispose();
    _customTomController.dispose();
    _newShiftNameController.dispose();
    super.dispose();
  }

  Future<void> _fetchAutoLocation() async {
    setState(() => _isFetchingLocation = true);
    try {
      final pos = await LocationService.getCurrentCoordinates();
      _latController.text = pos.latitude.toString();
      _lngController.text = pos.longitude.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Coordinates captured!'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  void _addTomSystem() {
    final text = _customTomController.text.trim();
    if (text.isNotEmpty && !_tomSystems.contains(text)) {
      setState(() {
        _tomSystems.add(text);
        _customTomController.clear();
      });
    }
  }

  void _addShiftTemplate() {
    final name = _newShiftNameController.text.trim();
    if (name.isEmpty) return;
    final startStr =
        '${_newShiftStart.hour.toString().padLeft(2, '0')}:${_newShiftStart.minute.toString().padLeft(2, '0')}:00';
    final endStr =
        '${_newShiftEnd.hour.toString().padLeft(2, '0')}:${_newShiftEnd.minute.toString().padLeft(2, '0')}:00';

    setState(() {
      _shiftTemplates.add({'name': name, 'start': startStr, 'end': endStr});
      _newShiftNameController.text = 'Shift ${_shiftTemplates.length + 1}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(stationActionNotifierProvider);
    final isEditing = widget.station != null;

    return Scaffold(
      appBar: AppBar(
          title: Text(isEditing ? 'Edit Station' : 'Create Metro Station')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: 'Station Name', border: OutlineInputBorder()),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Station name required'
                    : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latController,
                      decoration: const InputDecoration(
                          labelText: 'Latitude', border: OutlineInputBorder()),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _lngController,
                      decoration: const InputDecoration(
                          labelText: 'Longitude', border: OutlineInputBorder()),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                      backgroundColor: const Color(0xFF1E3A8A),
                    ),
                    onPressed: _isFetchingLocation ? null : _fetchAutoLocation,
                    icon: _isFetchingLocation
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.my_location, color: Colors.white),
                    label: const Text('Auto Set',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _radiusController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Punch Radius (M)',
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Fixed Daily Rate (₹)',
                          border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Add Station Shifts (e.g. A Shift, B Shift)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Card(
                color: Colors.grey.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _newShiftNameController,
                        decoration: const InputDecoration(
                            labelText: 'Shift Name',
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final t = await showTimePicker(
                                    context: context,
                                    initialTime: _newShiftStart);
                                if (t != null)
                                  setState(() => _newShiftStart = t);
                              },
                              child: Text(
                                  'Start: ${_newShiftStart.format(context)}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final t = await showTimePicker(
                                    context: context,
                                    initialTime: _newShiftEnd);
                                if (t != null) setState(() => _newShiftEnd = t);
                              },
                              child:
                                  Text('End: ${_newShiftEnd.format(context)}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _addShiftTemplate,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Shift'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _shiftTemplates.length,
                itemBuilder: (ctx, i) {
                  final item = _shiftTemplates[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.alarm, color: Color(0xFF1E3A8A)),
                    title: Text(
                        '${item['name']}: ${item['start']} - ${item['end']}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle,
                          color: Colors.redAccent),
                      onPressed: () =>
                          setState(() => _shiftTemplates.removeAt(i)),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              const Text('TOM Operating Systems',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customTomController,
                      decoration: const InputDecoration(
                          hintText: 'Add Counter (e.g. TOM 03)',
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                      onPressed: _addTomSystem, child: const Text('Add')),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                children: _tomSystems
                    .map((sys) => Chip(
                          label: Text(sys),
                          onDeleted: () =>
                              setState(() => _tomSystems.remove(sys)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: actionState.isLoading
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) return;
                        if (_shiftTemplates.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Please add at least one shift template.'),
                                backgroundColor: Colors.redAccent),
                          );
                          return;
                        }
                        await ref
                            .read(stationActionNotifierProvider.notifier)
                            .saveStation(
                              stationId: widget.station?.id,
                              name: _nameController.text.trim(),
                              latitude:
                                  double.parse(_latController.text.trim()),
                              longitude:
                                  double.parse(_lngController.text.trim()),
                              punchRadius:
                                  int.tryParse(_radiusController.text.trim()) ??
                                      600,
                              fixedAmount: double.tryParse(
                                      _amountController.text.trim()) ??
                                  700.00,
                              tomSystems: _tomSystems,
                              shiftTemplates: _shiftTemplates,
                            );
                        if (mounted) Navigator.pop(context);
                      },
                child: actionState.isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        isEditing
                            ? 'Update Metro Station'
                            : 'Save Metro Station',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
