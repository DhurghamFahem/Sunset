import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/order.dart';
import '../../models/prime_location.dart';

class PrimeAddressFields extends StatefulWidget {
  const PrimeAddressFields({
    super.key,
    required this.order,
    required this.enabled,
    required this.onChanged,
  });
  final TattooOrder order;
  final bool enabled;
  final void Function(PrimeLocation? state, PrimeLocation? district) onChanged;
  @override
  State<PrimeAddressFields> createState() => _PrimeAddressFieldsState();
}

class _PrimeAddressFieldsState extends State<PrimeAddressFields>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  List<PrimeLocation> states = [], districts = [];
  PrimeLocation? state, district;
  bool started = false, loadingStates = true, loadingDistricts = false;
  String? error;
  int generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      loadStates();
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  PrimeLocation? match(List<PrimeLocation> options, String? id, String name) {
    final matches = options
        .where(
          (option) => id != null
              ? option.id == id
              : option.name.trim() == name.trim() || option.id == name.trim(),
        )
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  Future<void> loadStates() async {
    final ticket = ++generation;
    setState(() {
      loadingStates = true;
      error = null;
    });
    try {
      final options = await AppScope.of(context).orders
          .primeLocations(widget.order.id);
      if (!mounted || ticket != generation) return;
      setState(() {
        states = options;
        state = match(
          options,
          state?.id ?? widget.order.primeStateId,
          widget.order.governorate,
        );
        loadingStates = false;
      });
      if (state != null) {
        await loadDistricts(restore: true);
      } else {
        widget.onChanged(null, null);
      }
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(() {
          loadingStates = false;
          error = e is OrderException
              ? e.message
              : 'تعذر تحميل المحافظات من برايم';
        });
      }
    }
  }

  Future<void> loadDistricts({bool restore = false}) async {
    final selected = state;
    if (selected == null) return;
    final ticket = ++generation;
    final previous = district;
    setState(() {
      districts = [];
      district = null;
      loadingDistricts = true;
      error = null;
    });
    if (!restore) widget.onChanged(selected, null);
    try {
      final options = await AppScope.of(context).orders
          .primeLocations(widget.order.id, stateId: selected.id);
      if (!mounted || ticket != generation) return;
      setState(() {
        districts = options;
        district = restore
            ? match(
                options,
                previous?.id ?? widget.order.primeDistrictId?.toString(),
                widget.order.area,
              )
            : null;
        loadingDistricts = false;
      });
      widget.onChanged(selected, district);
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(() {
          loadingDistricts = false;
          error = e is OrderException
              ? e.message
              : 'تعذر تحميل المناطق من برايم';
        });
        widget.onChanged(selected, null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<PrimeLocation>(
          key: ValueKey('prime-state-${state?.id}'),
          initialValue: state,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'المحافظة *'),
          items: states
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option.name)),
              )
              .toList(),
          onChanged: !widget.enabled || loadingStates
              ? null
              : (value) {
                  setState(() => state = value);
                  loadDistricts();
                },
          validator: (value) =>
              widget.enabled && value == null ? 'اختر المحافظة من برايم' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<PrimeLocation>(
          key: ValueKey('prime-district-${state?.id}-${district?.id}'),
          initialValue: district,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'المنطقة *'),
          items: districts
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option.name)),
              )
              .toList(),
          onChanged: !widget.enabled || loadingDistricts || state == null
              ? null
              : (value) {
                  setState(() => district = value);
                  widget.onChanged(state, value);
                },
          validator: (value) =>
              widget.enabled && value == null ? 'اختر المنطقة من برايم' : null,
        ),
        if (loadingStates || loadingDistricts) const LinearProgressIndicator(),
        if (error != null) ...[
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(
            onPressed: loadingStates || loadingDistricts
                ? null
                : () => states.isEmpty
                      ? loadStates()
                      : loadDistricts(restore: true),
            child: const Text('إعادة تحميل عناوين برايم'),
          ),
        ],
        if (!loadingStates && states.isEmpty && error == null)
          const Text('لا توجد محافظات متاحة في برايم'),
        if (state != null &&
            !loadingDistricts &&
            districts.isEmpty &&
            error == null)
          const Text('لا توجد مناطق متاحة لهذه المحافظة'),
        const SizedBox(height: 12),
      ],
    );
  }
}
