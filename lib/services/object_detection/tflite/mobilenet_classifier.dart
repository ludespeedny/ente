import 'dart:math';

import 'package:image/image.dart' as imageLib;
import "package:logging/logging.dart";
import 'package:photos/services/object_detection/models/predictions.dart';
import 'package:photos/services/object_detection/models/recognition.dart';
import "package:photos/services/object_detection/models/stats.dart";
import "package:photos/services/object_detection/tflite/classifier.dart";
import "package:tflite_flutter/tflite_flutter.dart";
import "package:tflite_flutter_helper/tflite_flutter_helper.dart";

// Source: https://tfhub.dev/tensorflow/lite-model/mobilenet_v1_1.0_224/1/default/1
class MobileNetClassifier extends Classifier {
  final _logger = Logger("MobileNetClassifier");

  /// Instance of Interpreter
  late Interpreter _interpreter;

  /// Labels file loaded as list
  late List<String> _labels;

  /// Input size of image (height = width = 300)
  static const int inputSize = 224;

  /// Result score threshold
  static const double threshold = 0.5;

  static const String modelFileName = "mobilenet_v1_1.0_224_quant.tflite";
  static const String labelFileName = "labels_mobilenet_quant_v1_224.txt";

  /// [ImageProcessor] used to pre-process the image
  ImageProcessor? imageProcessor;

  /// Padding the image to transform into square
  late int padSize;

  /// Shapes of output tensors
  late List<List<int>> _outputShapes;

  /// Types of output tensors
  late List<TfLiteType> _outputTypes;

  /// Number of results to show
  static const int numResults = 10;

  MobileNetClassifier({
    Interpreter? interpreter,
    List<String>? labels,
  }) {
    loadModel(interpreter);
    loadLabels(labels);
  }

  /// Loads interpreter from asset
  void loadModel(Interpreter? interpreter) async {
    try {
      _interpreter = interpreter ??
          await Interpreter.fromAsset(
            "models/mobilenet/" + modelFileName,
            options: InterpreterOptions()..threads = 4,
          );
      final outputTensors = _interpreter.getOutputTensors();
      _outputShapes = [];
      _outputTypes = [];
      outputTensors.forEach((tensor) {
        _outputShapes.add(tensor.shape);
        _outputTypes.add(tensor.type);
      });
      _logger.info("Interpreter initialized");
    } catch (e, s) {
      _logger.severe("Error while creating interpreter", e, s);
    }
  }

  /// Loads labels from assets
  void loadLabels(List<String>? labels) async {
    try {
      _labels = labels ??
          await FileUtil.loadLabels("assets/models/mobilenet/" + labelFileName);
      _logger.info("Labels initialized");
    } catch (e, s) {
      _logger.severe("Error while loading labels", e, s);
    }
  }

  /// Pre-process the image
  TensorImage _getProcessedImage(TensorImage inputImage) {
    padSize = max(inputImage.height, inputImage.width);
    imageProcessor ??= ImageProcessorBuilder()
        // .add(ResizeWithCropOrPadOp(padSize, padSize))
        .add(ResizeOp(inputSize, inputSize, ResizeMethod.BILINEAR))
        .build();
    inputImage = imageProcessor!.process(inputImage);
    return inputImage;
  }

  /// Runs object detection on the input image
  Predictions? predict(imageLib.Image image) {
    final predictStartTime = DateTime.now().millisecondsSinceEpoch;

    final preProcessStart = DateTime.now().millisecondsSinceEpoch;

    // Create TensorImage from image
    TensorImage inputImage = TensorImage.fromImage(image);

    // Pre-process TensorImage
    inputImage = _getProcessedImage(inputImage);

    final preProcessElapsedTime =
        DateTime.now().millisecondsSinceEpoch - preProcessStart;

    // TensorBuffers for output tensors
    final output = TensorBufferUint8(_outputShapes[0]);
    final inferenceTimeStart = DateTime.now().millisecondsSinceEpoch;
    // run inference
    _interpreter.run(inputImage.buffer, output.buffer);

    final inferenceTimeElapsed =
        DateTime.now().millisecondsSinceEpoch - inferenceTimeStart;

    final recognitions = <Recognition>[];
    for (int i = 0; i < 1001; i++) {
      final score = output.getDoubleValue(i) / 255;
      if (score >= threshold) {
        final label = _labels.elementAt(i);

        recognitions.add(
          Recognition(i, label, score),
        );
      }
    }

    final predictElapsedTime =
        DateTime.now().millisecondsSinceEpoch - predictStartTime;
    _logger.info(recognitions);
    return Predictions(
      recognitions,
      Stats(
        predictElapsedTime,
        predictElapsedTime,
        inferenceTimeElapsed,
        preProcessElapsedTime,
      ),
    );
  }

  /// Gets the interpreter instance
  Interpreter get interpreter => _interpreter;

  /// Gets the loaded labels
  List<String> get labels => _labels;
}
