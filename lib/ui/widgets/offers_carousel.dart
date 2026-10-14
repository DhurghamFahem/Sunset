import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../models/offer.dart';
import '../theme.dart';
import 'common.dart';
import 'offer_inquiry.dart';

class OffersCarousel extends StatefulWidget {
  const OffersCarousel({super.key});

  @override
  State<OffersCarousel> createState() => _OffersCarouselState();
}

class _OffersCarouselState extends State<OffersCarousel>
    with WidgetsBindingObserver {
  final pages = PageController();
  Timer? autoScroll;
  bool paused = false, hovered = false, touching = false;
  bool active = true, visible = true, motionAllowed = true;
  List<TattooOffer> offers = [];
  bool started = false, loading = true, failed = false;
  int current = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    visible = TickerMode.valuesOf(context).enabled;
    motionAllowed = !MediaQuery.disableAnimationsOf(context);
    if (!started) {
      started = true;
      load();
    }
    scheduleAutoScroll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    scheduleAutoScroll();
  }

  void scheduleAutoScroll() {
    autoScroll?.cancel();
    if (!mounted ||
        loading ||
        offers.length < 2 ||
        paused ||
        hovered ||
        touching ||
        !active ||
        !visible ||
        !motionAllowed) {
      return;
    }
    autoScroll = Timer(const Duration(seconds: 5), () {
      if (!pages.hasClients || pages.position.isScrollingNotifier.value) {
        scheduleAutoScroll();
        return;
      }
      move((current + 1) % offers.length);
    });
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final result = await AppScope.of(context).offers.list();
      if (!mounted) return;
      setState(() {
        offers = result;
        current = 0;
      });
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) {
        setState(() => loading = false);
        scheduleAutoScroll();
      }
    }
  }

  @override
  void dispose() {
    autoScroll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    pages.dispose();
    super.dispose();
  }

  Future<void> move(int page) async {
    autoScroll?.cancel();
    await pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    if (mounted) scheduleAutoScroll();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox.shrink();
    if (failed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const Expanded(child: Text('تعذر تحميل العروض')),
            TextButton(onPressed: load, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    if (offers.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return MouseRegion(
      onEnter: (_) {
        hovered = true;
        scheduleAutoScroll();
      },
      onExit: (_) {
        hovered = false;
        scheduleAutoScroll();
      },
      child: Listener(
        onPointerDown: (_) {
          touching = true;
          scheduleAutoScroll();
        },
        onPointerUp: (_) {
          touching = false;
          scheduleAutoScroll();
        },
        onPointerCancel: (_) {
          touching = false;
          scheduleAutoScroll();
        },
        child: Padding(
          key: const ValueKey('home-offers'),
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'عروض تستاهلها',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/offers'),
                    child: const Text('كل العروض'),
                  ),
                ],
              ),
              SizedBox(
                height: 270 + (scale > 1 ? (scale - 1) * 150 : 0),
                child: PageView.builder(
                  key: const ValueKey('offers-pages'),
                  controller: pages,
                  itemCount: offers.length,
                  onPageChanged: (index) => setState(() => current = index),
                  itemBuilder: (context, index) {
                    final offer = offers[index];
                    return Semantics(
                      label: 'عرض ${index + 1} من ${offers.length}',
                      child: Container(
                        key: ValueKey('carousel-offer-${offer.id}'),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: sage,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              offer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              '${offer.formattedPrice} • ${offer.products.length} وشم • بدون التوصيل',
                              maxLines: 2,
                              style: const TextStyle(
                                color: forest,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Row(
                                children: [
                                  for (final product in offer.products.take(3))
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                        ),
                                        child: CatalogImage(
                                          product.thumbnail,
                                          padding: 4,
                                        ),
                                      ),
                                    ),
                                  if (offer.products.length > 3)
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        '+${offer.products.length - 3}',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => inquireAboutOffer(
                                      context,
                                      offer,
                                      instagram: true,
                                    ),
                                    child: const Text('إنستغرام'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        inquireAboutOffer(context, offer),
                                    child: const Text('واتساب'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (offers.length > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (motionAllowed)
                      IconButton(
                        tooltip: paused
                            ? 'تشغيل التنقل التلقائي'
                            : 'إيقاف التنقل التلقائي',
                        onPressed: () {
                          setState(() => paused = !paused);
                          scheduleAutoScroll();
                        },
                        icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                      ),
                    IconButton(
                      tooltip: 'العرض السابق',
                      onPressed: current == 0 ? null : () => move(current - 1),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Text(
                      '${current + 1} / ${offers.length}',
                      textDirection: TextDirection.ltr,
                      semanticsLabel:
                          'العرض ${current + 1} من ${offers.length}',
                    ),
                    IconButton(
                      tooltip: 'العرض التالي',
                      onPressed: current == offers.length - 1
                          ? null
                          : () => move(current + 1),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
