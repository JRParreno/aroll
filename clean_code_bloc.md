# AI Code Guide: How to Add New Features BLOC and Implement in UI

## structure for folder

- domain use case `domain/usecase/feature` find which one i give to you
- how you will create the screen UI `presentation/featureFolder/featureScreen.dart` 
- guide for where the bloc event,state,bloc `presentation/featureFolder/bloc/FeatureBlocName/Here` create a FeatureBlocName because in single screen we might have multiple bloc

---

## 1. First Check the return type and the parameter of my given usecase

## which will be the guide for you to create the BLOC

---

## 2. Guide How to create bloc even

- Create Main Abstract event and extends to Equatable
- check the response if I use pageable (PageData) then create next page search and fetch
- if one time call create a fetch only
- if one time send payload create submit/send Feature name event only like submit login we only need submitEvent of login
**Example:**

```dart
abstract class FeatureEvent extends to Equatable {
  const FeatureEvent();
  @override
  List<Object?> get props => [];
}

class FetchFeatureEvent  extends FeatureEvent {}
class NextPageFeatureEvent  extends FeatureEvent {
  const NextPageFeatureEvent({this.page = 1, this.size = 10, this.search});
  final int page;
  final int size;
  final String?  search;

  @override
  List<Object?> get props => [
    page,
    size,
    search,
  ];
}
<!-- only needed this to reset if the search is moving or changing  -->
class ResetFeatureEvent  extends FeatureEvent {}
<!-- use the two below if we need submit or save payload -->
class SaveFeatureEvent  extends FeatureEvent {}
class SubmitFeatureEvent  extends FeatureEvent {}

```

---

## 3. Guide how to Create a FeatureState for our feature

- Check this and use this if the display option is pageable `core/enum/stateEnum`. i will use a model PageData for our pageable if this is not the return dont create a pageable that will come from our our usecaseFeature 
- create abstrac main class for state
- Follow the pattern below for new functions and states depending on the response of usecase
- if pageable add the enum like the example below if not pageable dont
- always add copy with if successStateFeature
- the data if nullable or required or empty object or empty array is possible if we can avoid nullable much better
**Example:**

```dart
abstract class FeatureState extends to Equatable {
  const FeatureState();
  @override
  List<Object?> get props => [];
}

class InitialFeatureState  extends FeatureEvent {}
class LoadingFeatureState  extends FeatureEvent {}
class ErrorFeatureState  extends FeatureEvent {}
// pageable 
class SuccessFeatureState  extends FeatureEvent {
  SuccessFeatureState({required this.data, this.status = StateEnum.initial});
  // dependes on response from Usecase 
  // also check if required or i have nullable 
  final ResponseFromUsecase<T> data;
  final StateEnum status;
  @override
  List<Object?> get props => [
    status,
    data,
  ];
}
// not pageAble
class SuccessFeatureState  extends FeatureEvent {
  SuccessFeatureState({required this.data });
  final ResponseFromUsecae<T> data;
    @override
  List<Object?> get props => [
    data,
  ];
  
}



```

## 4th as for UI i will be the one who will integrate but add it in the DI

- `core/bloc_service_locator.dart` then add the created bloc here check the main code and follow the code pattern
- always add in bottom of this function

```dart

void initBloc(GetIt sl) {
  <!-- other bloc register above -->

  <!-- always add in bottom of this function -->
  <!-- with usecase -->
  sl.registerLazySingleton<NewFeatureBloc>(
      () => NewFeatureBloc(IfWithUsecase: sl<IfWithUsecase>()));
  <!-- without usecase -->
  sl.registerLazySingleton<NewFeatureBloc>(NewFeatureBloc.new);
}

```

