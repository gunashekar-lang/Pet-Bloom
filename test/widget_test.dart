import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_super_app/app/app.dart';
import 'package:pet_super_app/data/pet_mapper.dart';
import 'package:pet_super_app/data/product_mapper.dart';
import 'package:pet_super_app/models/chat_model.dart';
import 'package:pet_super_app/models/pet_model.dart';
import 'package:pet_super_app/models/product_model.dart';
import 'package:pet_super_app/services/auth_service.dart';
import 'package:pet_super_app/services/healthcare_service.dart';
import 'package:pet_super_app/services/messaging_service.dart';
import 'package:pet_super_app/services/notification_service.dart';
import 'package:pet_super_app/services/pet_repository.dart';
import 'package:pet_super_app/services/pet_service.dart';
import 'package:pet_super_app/services/product_repository.dart';
import 'package:pet_super_app/services/store_service.dart';
import 'package:pet_super_app/services/supabase_config.dart';
import 'package:pet_super_app/utils/helpers.dart';
import 'package:pet_super_app/utils/validators.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal local listing, standing in for what a real API would return.
PetModel buildPet({
  String id = 'pet_test',
  String name = 'Biscuit',
  double price = 250,
  bool vaccinated = true,
}) {
  return PetModel(
    id: id,
    name: name,
    species: PetSpecies.dog,
    breed: 'Labrador mix',
    age: PetAge.young,
    ageInMonths: 18,
    gender: 'Male',
    price: price,
    imageUrls: const [],
    seller: const SellerModel(
      id: 'seller_test',
      name: 'Sam Lee',
      avatarUrl: '',
      location: 'Austin, TX',
    ),
    description: 'Friendly and house trained.',
    vaccinated: vaccinated,
  );
}

ProductModel buildProduct({
  String id = 'prod_test',
  String name = 'Daily Food',
  double price = 20,
  int stock = 20,
}) {
  return ProductModel(
    id: id,
    name: name,
    brand: 'PetHub',
    category: ProductCategory.food,
    price: price,
    imageUrl: '',
    stock: stock,
  );
}

/// Reads a thread back out of the service, since the model is immutable and
/// each update replaces the stored instance.
ChatThread? threadById(MessagingService service, String id) =>
    service.threadById(id);

void main() {
  // The auth tests below read and write accounts through SharedPreferences,
  // which has no backing store under `flutter test` without this.
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  group('Validators', () {
    test('email rejects malformed addresses', () {
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('owner@example.com'), isNull);
    });

    test('password requires length and mixed characters', () {
      expect(Validators.password('short'), isNotNull);
      expect(Validators.password('nodigitshere'), isNotNull);
      expect(Validators.password('1234567'), isNotNull);
      expect(Validators.password('Str0ngPass'), isNull);
    });

    test('price accepts positive amounts only', () {
      expect(Validators.price('0'), isNotNull);
      expect(Validators.price('1200'), isNull);
    });
  });

  group('PetService', () {
    test('starts empty with no favourites', () {
      final service = PetService();
      expect(service.allPets, isEmpty);
      expect(service.myListings, isEmpty);
      expect(service.favoriteIds, isEmpty);
    });

    test('createListing stores local image paths and vaccinations', () async {
      final service = PetService();
      final record = VaccinationRecord(
        name: 'Rabies',
        dateGiven: DateTime.now().subtract(const Duration(days: 30)),
        nextDue: DateTime.now().add(const Duration(days: 335)),
      );

      final pet = await service.createListing(
        name: 'Luna',
        species: PetSpecies.cat,
        breed: 'Tabby',
        ageInMonths: 10,
        gender: 'Female',
        price: 120,
        description: 'Shy at first, very affectionate.',
        location: 'Bengaluru, KA',
        healthIssues: 'None known',
        negotiable: true,
        imagePaths: const ['/local/luna1.png', '/local/luna2.png'],
        vaccinations: [record],
      );

      expect(pet.imageUrls, ['/local/luna1.png', '/local/luna2.png']);
      expect(pet.image, '/local/luna1.png');
      expect(pet.vaccinations.single.name, 'Rabies');
      expect(pet.vaccinations.single.isOverdue, isFalse);
      expect(pet.hasVaccinations, isTrue);
      expect(pet.healthIssues, 'None known');
      expect(service.myListings.single.id, pet.id);
    });

    test('updating photos and vaccinations mutates the listing', () async {
      final service = PetService();
      final pet = await service.createListing(
        name: 'Rex',
        species: PetSpecies.dog,
        breed: 'Shepherd',
        ageInMonths: 36,
        gender: 'Male',
        price: 400,
        description: 'Calm and loyal.',
        location: 'Pune, MH',
        healthIssues: 'Mild skin sensitivity',
        negotiable: false,
      );

      service.updateListingImages(pet.id, ['/local/rex.png']);
      service.updateVaccinations(pet.id, [
        VaccinationRecord(
          name: 'Bordetella',
          dateGiven: DateTime(2024, 1, 1),
          nextDue: DateTime(2023, 1, 1),
        ),
      ]);

      final updated = service.petById(pet.id)!;
      expect(updated.image, '/local/rex.png');
      expect(updated.vaccinations.single.isOverdue, isTrue);
    });

    test('toggling a favourite adds then removes it', () {
      final service = PetService();

      service.toggleFavorite('pet_test');
      expect(service.favoriteIds, contains('pet_test'));
      expect(service.favoriteIds.length, 1);

      service.toggleFavorite('pet_test');
      expect(service.favoriteIds, isEmpty);
    });

    test('marking a listing sold moves it out of the active set', () async {
      final service = PetService();
      final pet = await service.createListing(
        name: 'Archie',
        species: PetSpecies.dog,
        breed: 'Beagle',
        ageInMonths: 24,
        gender: 'Male',
        price: 300,
        description: 'Friendly beagle.',
        location: 'Chennai, TN',
        healthIssues: 'None known',
        negotiable: true,
      );

      await service.markAsSold(pet.id);

      expect(service.allPets, isEmpty);
      expect(service.myListings.single.status, PetStatus.sold);
    });

    test('contactSeller records an enquiry', () async {
      final service = PetService();
      final pet = buildPet();

      final inquiry = await service.contactSeller(
        pet: pet,
        buyerId: 'buyer_1',
        buyerName: 'Alex Kim',
        message: 'Is Biscuit still available?',
      );

      expect(service.inquiries.single.id, inquiry.id);
      expect(inquiry.petId, pet.id);
    });
  });

  group('PetFilter', () {
    test('clear flags reset the price bounds', () {
      const filter = PetFilter();
      final withPrice = filter.copyWith(minPrice: 100, maxPrice: 900);

      expect(withPrice.activeCount, 1);
      expect(withPrice.copyWith(clearMinPrice: true).minPrice, isNull);
      expect(
        withPrice.copyWith(clearMinPrice: true, clearMaxPrice: true).isEmpty,
        isTrue,
      );
    });
  });

  group('StoreService', () {
    test('starts with an empty catalogue and cart', () {
      final service = StoreService();
      expect(service.allProducts, isEmpty);
      expect(service.cart, isEmpty);
      expect(service.cartTotal, 0);
    });

    test('cart totals respect the free shipping threshold', () {
      final service = StoreService();
      service.addToCart(buildProduct(price: 200), quantity: 2);

      expect(service.cartItemCount, 2);
      expect(service.cartSubtotal, 400);
      expect(
        service.cartShipping,
        49,
        reason: 'under the threshold ships paid',
      );
      expect(service.freeShippingGap, 99);
    });

    test('shipping is free at or above the threshold', () {
      final service = StoreService();
      service.addToCart(buildProduct(price: 250), quantity: 2);

      expect(service.cartSubtotal, 500);
      expect(service.cartShipping, 0);
    });

    test('placing an order moves the cart into order history', () async {
      final service = StoreService();
      service.addToCart(buildProduct());

      final order = await service.placeOrder(
        address: '1 Test Street, Austin, TX',
      );

      expect(service.orders.single.id, order.id);
      expect(service.cart, isEmpty);
      expect(order.items, isNotEmpty);
      expect(service.activeOrders.length, 1);
    });

    test('placing an order with an empty cart throws', () async {
      final service = StoreService();
      expect(
        () => service.placeOrder(address: '1 Test Street'),
        throwsStateError,
      );
    });
  });

  group('NotificationService', () {
    test('starts empty and tracks unread count', () {
      final service = NotificationService();
      expect(service.isEmpty, isTrue);
      expect(service.unreadCount, 0);

      service.reminder(title: 'Heads up', body: 'Nothing to do yet');

      expect(service.isEmpty, isFalse);
      expect(service.unreadCount, 1);
      expect(service.items.first.isRead, isFalse);
    });

    test('markRead and markAllRead clear the badge', () {
      final service = NotificationService();
      final first = service.reminder(title: 'One', body: 'First');
      service.reminder(title: 'Two', body: 'Second');

      service.markRead(first.id);
      expect(service.unreadCount, 1);

      service.markAllRead();
      expect(service.unreadCount, 0);
    });

    test('listing notifications target the pet details route', () {
      final service = NotificationService();
      final n = service.listingPublished(petName: 'Luna', petId: 'pet_1');

      expect(n.kind, NotificationKind.listing);
      expect(n.targetRoute, isNotNull);
      expect(n.targetArguments, isNotNull);
    });

    test('remove and reset empty the inbox', () {
      final service = NotificationService();
      final n = service.reminder(title: 'One', body: 'First');

      service.remove(n.id);
      expect(service.isEmpty, isTrue);

      service.enquirySent(petName: 'Biscuit', petId: 'pet_2');
      expect(service.isEmpty, isFalse);

      service.reset();
      expect(service.isEmpty, isTrue);
    });
  });

  group('HealthcareService', () {
    test('exposes tips and guides with no clinics or bookings', () {
      final service = HealthcareService();

      expect(service.tips, isNotEmpty);
      expect(service.articles, isNotEmpty);
      expect(service.faqs, isNotEmpty);
    });

    test('article search filters by title, summary and body', () {
      final service = HealthcareService();
      final target = service.articles.first;

      service.setArticleQuery(target.title.split(' ').first);

      expect(service.articleResults, isNotEmpty);
      expect(service.articleResults.any((a) => a.id == target.id), isTrue);
    });

    test('articleById resolves known ids only', () {
      final service = HealthcareService();

      expect(service.articleById(service.articles.first.id), isNotNull);
      expect(service.articleById('missing'), isNull);
    });
  });

  group('MessagingService', () {
    test('starts with an empty inbox', () {
      final service = MessagingService();

      expect(service.isEmpty, isTrue);
      expect(service.threads, isEmpty);
      expect(service.unreadCount, 0);
    });

    test('buyer side talks to the seller of the listing', () {
      final service = MessagingService();
      final thread = service.openThread(pet: buildPet(), role: ChatRole.buyer);

      expect(thread.participantName, 'Sam Lee');
      expect(thread.counterpartyIsBuyer, isFalse);
      expect(service.threads.single.id, thread.id);
    });

    test('seller side talks to a buyer about their own listing', () {
      final service = MessagingService();
      final thread = service.openThread(
        pet: buildPet(),
        role: ChatRole.seller,
        counterpartyName: 'Alex Kim',
      );

      expect(thread.participantName, 'Alex Kim');
      expect(thread.counterpartyIsBuyer, isTrue);
      expect(thread.participantInitials, 'AK');
    });

    test('the same listing keeps one thread per side', () {
      final service = MessagingService();
      final first = service.openThread(pet: buildPet(), role: ChatRole.buyer);
      final again = service.openThread(pet: buildPet(), role: ChatRole.buyer);

      expect(again.id, first.id);
      expect(service.threads.length, 1);
    });

    test('a received message raises a notification for the thread', () async {
      final notifications = NotificationService();
      late ChatThread receivedIn;
      late ChatMessage received;
      final service = MessagingService(
        onMessageReceived: (thread, message) {
          receivedIn = thread;
          received = message;
        },
      );
      final thread = service.openThread(pet: buildPet(), role: ChatRole.buyer);

      await service.send(thread.id, 'Is Biscuit still available?');
      expect(threadById(service, thread.id)!.messages.single.isMine, isTrue);

      service.receive(thread.id, 'Yes, still available.');
      service.dispose();

      expect(receivedIn.id, thread.id);
      expect(received.isMine, isFalse);
      expect(notifications.isEmpty, isTrue);
    });

    test('markRead clears the badge and flags outgoing messages read', () {
      final service = MessagingService();
      final thread = service.openThread(pet: buildPet(), role: ChatRole.buyer);

      service.receive(thread.id, 'Sure, I can send more photos.');
      expect(service.unreadCount, 1);

      service.markRead(thread.id);
      final cleared = service.threadById(thread.id)!;
      expect(cleared.unreadCount, 0);
      expect(service.unreadCount, 0);
    });

    test('deleteThread and reset empty the inbox', () {
      final service = MessagingService();
      final thread = service.openThread(pet: buildPet(), role: ChatRole.buyer);

      service.deleteThread(thread.id);
      expect(service.isEmpty, isTrue);

      service.openThread(pet: buildPet(), role: ChatRole.seller);
      service.reset();
      expect(service.isEmpty, isTrue);
    });
  });

  group('Currency', () {
    test('prices render in rupees with Indian digit grouping', () {
      expect(Helpers.currency(4500), contains('₹'));
      expect(Helpers.currency(4500), '₹4,500');
      // Indian grouping puts a comma after the first two thousand digits.
      expect(Helpers.currency(120000), '₹1,20,000');
      expect(Helpers.formatPrice(120000), '₹1.2L');
      expect(Helpers.formatPrice(45000), '₹45k');
    });

    test('no dollar symbols remain in formatting helpers', () {
      expect(Helpers.currency(99), isNot(contains(r'$')));
      expect(Helpers.currencyPrecise(99.5), isNot(contains(r'$')));
      expect(Helpers.formatPrice(99), isNot(contains(r'$')));
    });
  });

  group('Sign-in validation', () {
    test('accepts a valid email address', () {
      expect(Validators.emailOrPhone('user@example.com'), isNull);
    });

    test('accepts a 10 digit Indian mobile number', () {
      expect(Validators.emailOrPhone('9876543210'), isNull);
      expect(Validators.emailOrPhone('6123456789'), isNull);
      expect(Validators.emailOrPhone('8123456789'), isNull);
      expect(Validators.emailOrPhone('9123456789'), isNull);
    });

    test('rejects numbers that do not start with 6-9', () {
      expect(Validators.emailOrPhone('1234567890'), isNotNull);
      expect(Validators.emailOrPhone('5123456789'), isNotNull);
    });

    test('rejects the wrong number of digits', () {
      expect(Validators.emailOrPhone('987654321'), isNotNull);
      expect(Validators.emailOrPhone('98765432100'), isNotNull);
    });

    test('normalises +91 and spacing before checking', () {
      expect(Validators.normalizeIndianPhone('+91 98765 43210'), '9876543210');
      expect(Validators.emailOrPhone('+91 98765 43210'), isNull);
      expect(Validators.emailOrPhone('98765-43210'), isNull);
    });

    test('phone validator follows the same Indian rules', () {
      expect(Validators.phone('9876543210'), isNull);
      expect(Validators.phone('1234567890'), isNotNull);
      expect(Validators.phone('98765432'), isNotNull);
    });
  });

  group('AuthService without a configured backend', () {
    late AuthService auth;

    setUp(() {
      // Force the unconfigured path: a developer's real .env must not decide
      // which branch these tests run. Each test starts with an empty local
      // account store.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      SupabaseConfig.debugReset();
      SupabaseConfig.debugForceMissingCredentials = true;
      auth = AuthService();
    });

    tearDown(() {
      auth.dispose();
      SupabaseConfig.debugReset();
    });

    test('bootstrap completes and reports no backend', () async {
      await auth.bootstrap();
      expect(auth.isInitialising, isFalse);
      expect(auth.isBackendConfigured, isFalse);
      expect(auth.isLoggedIn, isFalse);
      expect(auth.user, isNull);
    });

    test('login rejects empty input before touching the network', () async {
      await auth.bootstrap();
      final ok = await auth.login('   ', '');
      expect(ok, isFalse);
      expect(auth.isLoading, isFalse);
      expect(auth.error, contains('email or mobile number'));
    });

    test('login rejects a malformed identifier', () async {
      await auth.bootstrap();
      final ok = await auth.login('not-an-email', 'Password1!');
      expect(ok, isFalse);
      expect(auth.error, contains('valid email address'));
    });

    test('a phone identifier passes validation then looks for a local account', () async {
      await auth.bootstrap();
      // The phone is recognised as a phone, not rejected as a bad email. With
      // no backend the flow stops at the local account lookup.
      final ok = await auth.login('9876543210', 'Password1!');
      expect(ok, isFalse);
      expect(auth.error, isNot(contains('valid email address')));
      expect(auth.error, contains('No local account'));
    });

    test('login without a matching local account explains what to do', () async {
      await auth.bootstrap();
      final ok = await auth.login('user@example.com', 'Password1!');
      expect(ok, isFalse);
      expect(auth.error, contains('No local account'));
    });

    test('register validates fields before contacting Supabase', () async {
      await auth.bootstrap();
      expect(
        await auth.register(
          fullName: '',
          email: 'user@example.com',
          phone: '9876543210',
          password: 'Password1!',
        ),
        isFalse,
      );
      expect(auth.error, contains('full name'));

      expect(
        await auth.register(
          fullName: 'Asha Rao',
          email: 'bad-email',
          phone: '9876543210',
          password: 'Password1!',
        ),
        isFalse,
      );
      expect(auth.error, isNotNull);
    });

    test('register creates a local account and signs in', () async {
      await auth.bootstrap();
      final ok = await auth.register(
        fullName: 'Asha Rao',
        email: 'asha@example.com',
        phone: '+91 98765 43210',
        password: 'Password1!',
      );
      expect(ok, isTrue);
      expect(auth.isLoggedIn, isTrue);
      expect(auth.user?.fullName, 'Asha Rao');
      // The phone is normalised, not stored with +91 or spacing.
      expect(auth.user?.phone, '9876543210');
      expect(auth.user?.id, startsWith('local_'));
    });

    test('a local account can sign back in after logout', () async {
      await auth.bootstrap();
      await auth.register(
        fullName: 'Asha Rao',
        email: 'asha@example.com',
        phone: '9876543210',
        password: 'Password1!',
      );
      await auth.logout();
      expect(auth.isLoggedIn, isFalse);

      final ok = await auth.login('asha@example.com', 'Password1!');
      expect(ok, isTrue);
      expect(auth.isLoggedIn, isTrue);
      expect(auth.user?.fullName, 'Asha Rao');
    });

    test('a wrong password is rejected for a local account', () async {
      await auth.bootstrap();
      await auth.register(
        fullName: 'Asha Rao',
        email: 'asha@example.com',
        phone: '9876543210',
        password: 'Password1!',
      );
      await auth.logout();

      final ok = await auth.login('asha@example.com', 'WrongPass1!');
      expect(ok, isFalse);
      expect(auth.error, contains('Incorrect password'));
    });

    test('registering the same identifier twice is refused', () async {
      await auth.bootstrap();
      await auth.register(
        fullName: 'Asha Rao',
        email: 'asha@example.com',
        phone: '9876543210',
        password: 'Password1!',
      );
      await auth.logout();

      final ok = await auth.register(
        fullName: 'Asha Rao',
        email: 'asha@example.com',
        phone: '9876543210',
        password: 'Password1!',
      );
      expect(ok, isFalse);
      expect(auth.error, contains('already exists'));
    });

    test('logout clears local state', () async {
      await auth.bootstrap();
      await auth.logout();
      expect(auth.isLoggedIn, isFalse);
      expect(auth.user, isNull);
    });

    test('a local session is restored after an app restart', () async {
      await auth.bootstrap();
      await auth.register(
        fullName: 'Asha Rao',
        email: 'asha@example.com',
        phone: '9876543210',
        password: 'Password1!',
      );
      expect(auth.isLoggedIn, isTrue);

      // A fresh service over the same storage models the next cold start.
      final restarted = AuthService();
      await restarted.bootstrap();
      expect(restarted.isLoggedIn, isTrue);
      expect(restarted.user?.fullName, 'Asha Rao');
      expect(restarted.user?.phone, '9876543210');
      restarted.dispose();
    });

    test('logging out stops the session being restored', () async {
      await auth.bootstrap();
      await auth.register(
        fullName: 'Asha Rao',
        email: 'asha@example.com',
        phone: '9876543210',
        password: 'Password1!',
      );
      await auth.logout();

      final restarted = AuthService();
      await restarted.bootstrap();
      expect(restarted.isLoggedIn, isFalse);
      expect(restarted.user, isNull);
      restarted.dispose();
    });

    test('a profile edit is remembered across a restart', () async {
      await auth.bootstrap();
      await auth.register(
        fullName: 'Asha Rao',
        email: 'asha@example.com',
        phone: '9876543210',
        password: 'Password1!',
      );
      auth.updateProfile(city: 'Pune', bio: 'Two rescues and a labradoodle');

      final restarted = AuthService();
      await restarted.bootstrap();
      expect(restarted.user?.city, 'Pune');
      expect(restarted.user?.bio, 'Two rescues and a labradoodle');
      restarted.dispose();
    });
  });

  group('SupabaseConfig', () {
    tearDown(SupabaseConfig.debugReset);

    test('client getter throws a clear error before initialisation', () {
      SupabaseConfig.debugReset();
      expect(SupabaseConfig.isInitialised, isFalse);
      expect(() => SupabaseConfig.client, throwsStateError);
    });

    test('ensureInit returns false when no credentials exist', () async {
      SupabaseConfig.debugReset();
      final ok = await SupabaseConfig.ensureInit(loadEnvFile: false);
      expect(ok, isFalse);
      expect(SupabaseConfig.isInitialised, isFalse);
    });
  });

  group('Sell a product and shop ownership', () {
    test('a published product is owned by the seller shop', () async {
      final service = StoreService();
      final product = await service.createProductListing(
        name: 'Chicken Jerky',
        brand: '',
        category: ProductCategory.treats,
        price: 249,
        stock: 12,
      );

      expect(product.sellerId, isNotEmpty);
      expect(product.shopName, service.shopName);
      expect(product.ownedBy('me'), isTrue);
      expect(product.isVerifiedShopListing, isFalse);
      expect(service.myShopProducts.single.id, product.id);
      expect(service.shopProductCount, 1);
    });

    test('verifying the shop badges every product it owns', () async {
      final service = StoreService();
      await service.createProductListing(
        name: 'Rope Toy',
        brand: '',
        category: ProductCategory.toys,
        price: 399,
        stock: 4,
      );

      service.setShopVerified(true);

      final product = service.myShopProducts.single;
      expect(product.isVerifiedShopListing, isTrue);
      expect(product.shopName, service.shopName);
    });

    test('deleting a product also removes it from the cart', () async {
      final service = StoreService();
      final product = await service.createProductListing(
        name: 'Grooming Brush',
        brand: '',
        category: ProductCategory.grooming,
        price: 199,
        stock: 3,
      );
      service.addToCart(product);
      expect(service.cartItemCount, 1);

      await service.deleteProduct(product.id);
      expect(service.cartItemCount, 0);
      expect(service.myShopProducts, isEmpty);
    });

    test('the browse grid hides the products the seller owns', () async {
      final service = StoreService();
      final before = service.results.length;

      await service.createProductListing(
        name: 'Puppy Harness',
        brand: 'Walk',
        category: ProductCategory.walking,
        price: 599,
        stock: 5,
      );

      expect(service.myShopProducts.length, 1);
      expect(service.results.length, before);
      expect(
        service.results.any((p) => p.name == 'Puppy Harness'),
        isFalse,
      );
    });
  });

  group('Pet health fields', () {
    test('vaccination history drives the vaccinated flag', () async {
      final service = PetService();
      final pet = await service.createListing(
        name: 'Luna',
        species: PetSpecies.cat,
        breed: 'Tabby',
        ageInMonths: 10,
        gender: 'Female',
        price: 12000,
        description: 'Affectionate.',
        location: 'Bengaluru, KA',
        healthIssues: 'None known',
        negotiable: true,
        vaccinations: [
          VaccinationRecord(name: 'Rabies', dateGiven: DateTime(2025, 1, 1)),
        ],
      );

      expect(pet.vaccinated, isTrue);
      expect(pet.hasVaccinations, isTrue);
      expect(pet.hasHealthIssues, isFalse);
    });

    test('a disclosed health issue is flagged and lowers the score', () async {
      final service = PetService();
      final healthy = await service.createListing(
        name: 'Rocky',
        species: PetSpecies.dog,
        breed: 'Beagle',
        ageInMonths: 24,
        gender: 'Male',
        price: 30000,
        description: 'Calm.',
        location: 'Pune, MH',
        healthIssues: 'None known',
        negotiable: false,
      );
      final flagged = await service.createListing(
        name: 'Bella',
        species: PetSpecies.dog,
        breed: 'Poodle',
        ageInMonths: 36,
        gender: 'Female',
        price: 45000,
        description: 'Sweet.',
        location: 'Pune, MH',
        healthIssues: 'Early arthritis',
        negotiable: false,
      );

      expect(flagged.hasHealthIssues, isTrue);
      expect(flagged.healthScore, lessThan(healthy.healthScore));
    });
  });

  group('Own listings stay out of the buy page', () {
    test('a pet the seller listed is browseable only in My listings', () async {
      final service = PetService();
      final before = service.results.length;

      final pet = await service.createListing(
        name: 'Coco',
        species: PetSpecies.dog,
        breed: 'Indie',
        ageInMonths: 7,
        gender: 'Female',
        price: 15000,
        description: 'Playful.',
        location: 'Pune, MH',
        healthIssues: 'None known',
        negotiable: false,
      );

      expect(service.myListings.single.id, pet.id);
      expect(service.results.length, before);
      expect(service.results.any((p) => p.id == pet.id), isFalse);
    });

    test('searching for your own listing does not surface it', () async {
      final service = PetService();
      await service.createListing(
        name: 'Coco',
        species: PetSpecies.dog,
        breed: 'Indie',
        ageInMonths: 7,
        gender: 'Female',
        price: 15000,
        description: 'Playful.',
        location: 'Pune, MH',
        healthIssues: 'None known',
        negotiable: false,
      );

      service.setQuery('Coco');

      expect(service.myListings.length, 1);
      expect(service.results, isEmpty);
    });
  });

  group('Pet row mapping', () {
    PetModel sample() => PetModel(
      id: 'pet-1',
      name: 'Coco',
      species: PetSpecies.cat,
      breed: 'Tabby',
      ageInMonths: 7,
      age: PetAge.puppy,
      gender: 'Female',
      price: 12000,
      imageUrls: const ['https://cdn.test/a.jpg', 'https://cdn.test/b.jpg'],
      seller: const SellerModel(
        id: 'u1',
        name: 'Asha',
        avatarUrl: '',
      ),
      description: 'Playful.',
      vaccinated: true,
      healthIssues: 'None known',
      vaccinations: [
        VaccinationRecord(
          name: 'Rabies',
          dateGiven: DateTime(2025, 3, 4),
          vetName: 'Dr Rao',
        ),
      ],
      location: 'Pune, MH',
      status: PetStatus.available,
      negotiable: true,
      tags: const ['Cat', 'Puppy'],
      ownerId: 'u1',
    );

    test('a model round-trips through a database row without losing fields',
        () {
      final row = PetMapper.toRow(sample());
      final back = PetMapper.fromRow({
        ...row,
        'id': 'pet-1',
        'created_at': '2026-01-02T03:04:05Z',
      });

      expect(back.id, 'pet-1');
      expect(back.name, 'Coco');
      expect(back.species, PetSpecies.cat);
      expect(back.breed, 'Tabby');
      expect(back.ageInMonths, 7);
      expect(back.gender, 'Female');
      expect(back.price, 12000);
      expect(back.imageUrls, ['https://cdn.test/a.jpg', 'https://cdn.test/b.jpg']);
      expect(back.description, 'Playful.');
      expect(back.vaccinated, isTrue);
      expect(back.healthIssues, 'None known');
      expect(back.location, 'Pune, MH');
      expect(back.status, PetStatus.available);
      expect(back.negotiable, isTrue);
      expect(back.tags, ['Cat', 'Puppy']);
      expect(back.ownerId, 'u1');
      expect(back.vaccinations.single.name, 'Rabies');
      expect(back.vaccinations.single.vetName, 'Dr Rao');
      expect(back.createdAt, DateTime.parse('2026-01-02T03:04:05Z'));
    });

    test('column names are snake_case and match the SQL file', () {
      final row = PetMapper.toRow(sample());
      expect(row.containsKey('age_in_months'), isTrue);
      expect(row.containsKey('image_urls'), isTrue);
      expect(row.containsKey('health_issues'), isTrue);
      expect(row.containsKey('seller_id'), isTrue);
      // The Dart camelCase names must never reach the database.
      expect(row.containsKey('ageInMonths'), isFalse);
      expect(row.containsKey('imageUrls'), isFalse);
      expect(row.containsKey('ownerId'), isFalse);
    });

    test('an unknown or missing value falls back instead of throwing', () {
      final back = PetMapper.fromRow({
        'id': 'pet-2',
        'name': 'Rocky',
        'species': 'dragon',
        'status': 'teleported',
        'condition': 'pristine',
        'gender': null,
        'price': null,
        'age_in_months': null,
        'image_urls': null,
        'tags': null,
        'vaccinations': null,
      });

      expect(back.species, PetSpecies.other);
      expect(back.status, PetStatus.available);
      expect(back.condition, PetCondition.excellent);
      expect(back.price, 0);
      expect(back.imageUrls, isEmpty);
      expect(back.vaccinations, isEmpty);
      expect(back.createdAt, isNull);
    });

    test('a patch touches only the columns the app can edit', () {
      final patch = PetMapper.toPatch(sample());
      expect(patch.containsKey('status'), isTrue);
      expect(patch.containsKey('price'), isTrue);
      // seller_id must never be in a patch or a listing could be stolen.
      expect(patch.containsKey('seller_id'), isFalse);
      expect(patch.containsKey('views'), isFalse);
    });
  });

  group('Pet listing without a backend', () {
    test('createListing still works offline and flags the write unsynced', () async {
      final service = PetService();
      final pet = await service.createListing(
        name: 'Milo',
        species: PetSpecies.dog,
        breed: 'Beagle',
        ageInMonths: 24,
        gender: 'Male',
        price: 20000,
        description: 'Calm.',
        location: 'Pune, MH',
        healthIssues: 'None known',
        negotiable: false,
      );

      expect(pet.name, 'Milo');
      expect(service.myListings.single.id, pet.id);
      // Offline there is no server to confirm the write, but the local copy
      // must still exist.
      expect(service.lastWriteSynced, isTrue);
      service.dispose();
    });

    test('the repository reports itself unavailable with no session', () {
      expect(PetRepository.instance.isAvailable, isFalse);
    });
  });

  group('Product row mapping', () {
    ProductModel sample() => const ProductModel(
      id: 'prod-1',
      name: 'Premium Dog Food',
      brand: 'PetHub',
      category: ProductCategory.food,
      price: 1200,
      oldPrice: 1500,
      imageUrl: 'https://cdn.test/food.jpg',
      description: 'Grain free.',
      highlights: ['High protein', 'No fillers'],
      stock: 20,
      soldCount: 5,
      isFeatured: true,
      isBestSeller: false,
      freeShipping: true,
      speciesTags: [PetSpecies.dog],
      sellerId: 'u1',
      shopName: 'Sam\'s Shop',
      shopVerified: true,
      rating: 4.8,
      reviewCount: 12,
    );

    test('a model round-trips through a database row without losing fields',
        () {
      final row = ProductMapper.toRow(sample());
      final back = ProductMapper.fromRow({
        ...row,
        'id': 'prod-1',
        'created_at': '2026-01-02T03:04:05Z',
      });

      expect(back.id, 'prod-1');
      expect(back.name, 'Premium Dog Food');
      expect(back.brand, 'PetHub');
      expect(back.category, ProductCategory.food);
      expect(back.price, 1200);
      expect(back.oldPrice, 1500);
      expect(back.imageUrl, 'https://cdn.test/food.jpg');
      expect(back.description, 'Grain free.');
      expect(back.highlights, ['High protein', 'No fillers']);
      expect(back.stock, 20);
      expect(back.soldCount, 5);
      expect(back.isFeatured, isTrue);
      expect(back.isBestSeller, isFalse);
      expect(back.freeShipping, isTrue);
      expect(back.speciesTags, [PetSpecies.dog]);
      expect(back.sellerId, 'u1');
      expect(back.shopName, 'Sam\'s Shop');
      expect(back.shopVerified, isTrue);
      expect(back.rating, 4.8);
      expect(back.reviewCount, 12);
    });

    test('column names are snake_case and match the SQL file', () {
      final row = ProductMapper.toRow(sample());
      expect(row.containsKey('seller_id'), isTrue);
      expect(row.containsKey('image_url'), isTrue);
      expect(row.containsKey('old_price'), isTrue);
      expect(row.containsKey('sold_count'), isTrue);
      expect(row.containsKey('species_tags'), isTrue);
      // The Dart camelCase names must never reach the database.
      expect(row.containsKey('sellerId'), isFalse);
      expect(row.containsKey('imageUrl'), isFalse);
      expect(row.containsKey('shopName'), isFalse);
      expect(row.containsKey('oldPrice'), isFalse);
      // id and created_at are owned by Postgres.
      expect(row.containsKey('id'), isFalse);
    });

    test('an unknown or missing value falls back instead of throwing', () {
      final back = ProductMapper.fromRow({
        'id': 'prod-2',
        'name': 'Toy',
        'brand': null,
        'category': 'gadget',
        'price': null,
        'old_price': null,
        'image_url': null,
        'highlights': null,
        'stock': null,
        'species_tags': null,
        'seller_id': null,
      });

      expect(back.category, ProductCategory.accessories);
      expect(back.price, 0);
      expect(back.oldPrice, isNull);
      expect(back.imageUrl, isEmpty);
      expect(back.highlights, isEmpty);
      expect(back.stock, 0);
      expect(back.speciesTags, isEmpty);
      expect(back.shopVerified, isFalse);
    });

    test('a patch touches only the columns the app can edit', () {
      final patch = ProductMapper.toPatch(sample());
      expect(patch.containsKey('price'), isTrue);
      expect(patch.containsKey('stock'), isTrue);
      // seller_id must never be in a patch or a listing could be stolen.
      expect(patch.containsKey('seller_id'), isFalse);
      expect(patch.containsKey('sold_count'), isFalse);
    });
  });

  group('Product listing without a backend', () {
    test('createProductListing still works offline and flags the write synced',
        () async {
      final service = StoreService();
      final product = await service.createProductListing(
        name: 'Chew Toy',
        brand: 'PetHub',
        category: ProductCategory.toys,
        price: 300,
      );

      expect(product.name, 'Chew Toy');
      expect(service.myShopProducts.single.id, product.id);
      // A seller's own product stays out of the browse grid.
      expect(service.results, isEmpty);
      expect(service.lastWriteSynced, isTrue);
      service.dispose();
    });

    test('the repository reports itself unavailable with no session', () {
      expect(ProductRepository.instance.isAvailable, isFalse);
    });
  });

  testWidgets('app boots to the splash screen', (tester) async {
    await tester.pumpWidget(const PetHubApp());
    await tester.pump();

    expect(find.text('petbloom'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Let the bootstrap delays settle so no timers outlive the test.
    await tester.pump(const Duration(seconds: 2));
  });
}
