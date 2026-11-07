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
    final ticket = ++generation;
    final previous = district;
    setState(() {
      districts = [];
      district = null;
      loadingDistricts = selected != null;
      error = null;
    });
    if (!restore) widget.onChanged(selected, null);
    if (selected == null) return;
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
        _LocationDropdown(
          key: ValueKey('prime-state-${state?.id}'),
          selection: state,
          label: 'المحافظة *',
          hint: 'ابحث عن المحافظة',
          validationMessage: 'اختر المحافظة من برايم',
          required: widget.enabled,
          enabled: widget.enabled && !loadingStates && states.isNotEmpty,
          options: states,
          onSelected: (value) {
            setState(() => state = value);
            loadDistricts();
          },
        ),
        const SizedBox(height: 12),
        _LocationDropdown(
          key: ValueKey('prime-district-${state?.id}-${district?.id}'),
          selection: district,
          label: 'المنطقة *',
          hint: 'ابحث عن المنطقة',
          validationMessage: 'اختر المنطقة من برايم',
          required: widget.enabled,
          enabled:
              widget.enabled &&
              !loadingDistricts &&
              state != null &&
              districts.isNotEmpty,
          options: districts,
          onSelected: (value) {
            setState(() => district = value);
            widget.onChanged(state, value);
          },
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

class _LocationDropdown extends StatefulWidget {
  const _LocationDropdown({
    super.key,
    required this.selection,
    required this.options,
    required this.label,
    required this.hint,
    required this.validationMessage,
    required this.required,
    required this.enabled,
    required this.onSelected,
  });

  final PrimeLocation? selection;
  final List<PrimeLocation> options;
  final String label, hint, validationMessage;
  final bool required, enabled;
  final ValueChanged<PrimeLocation?> onSelected;

  @override
  State<_LocationDropdown> createState() => _LocationDropdownState();
}

class _LocationDropdownState extends State<_LocationDropdown> {
  late final controller = TextEditingController(text: widget.selection?.name);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DropdownMenuFormField<PrimeLocation>(
    controller: controller,
    initialSelection: widget.selection,
    expandedInsets: EdgeInsets.zero,
    menuHeight: 280,
    enableFilter: true,
    requestFocusOnTap: true,
    label: Text(widget.label),
    hintText: widget.hint,
    enabled: widget.enabled,
    dropdownMenuEntries: widget.options
        .map((option) => DropdownMenuEntry(value: option, label: option.name))
        .toList(),
    onSelected: widget.onSelected,
    validator: (value) =>
        widget.required && (value == null || controller.text != value.name)
        ? widget.validationMessage
        : null,
  );
}
