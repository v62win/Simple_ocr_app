import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:image/image.dart' as img;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;

  const MyApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GOODYEAR SCANNER',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: MyHomePage(title: 'GOODYEAR TYRE SCANNER', camera: camera),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String title;
  final CameraDescription camera;

  const MyHomePage({super.key, required this.title, required this.camera});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final StreamController<String> controller = StreamController<String>();
  final TextEditingController _textController = TextEditingController();
  final double _textViewHeight = 100.0;
  CameraController? _cameraController;
  bool isProcessing = false;
  stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  // Define percentage for focus area size
  final double focusAreaWidthPercent = 0.9; // 90% of preview width
  final double focusAreaHeightPercent = 0.1; // 10% of preview height

  @override
  void initState() {
    super.initState();
    _cameraController = CameraController(widget.camera, ResolutionPreset.high);
    _cameraController?.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    controller.close();
    super.dispose();
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) => print('onStatus: $val'),
        onError: (val) => print('onError: $val'),
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(onResult: (val) => setState(() {
          _textController.text = val.recognizedWords;
        }));
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  Future<void> _captureImage() async {
    if (isProcessing) return;

    setState(() {
      isProcessing = true;
    });

    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String tempImagePath = join(tempDir.path, '${DateTime.now()}.png');

      final XFile image = await _cameraController!.takePicture();
      final File file = File(tempImagePath);
      await file.writeAsBytes(await image.readAsBytes());

      // Crop the image to the focused area and process it
      _processImage(tempImagePath);
    } catch (e) {
      print('Error capturing image: $e');
    }

    setState(() {
      isProcessing = false;
    });
  }

  Future<void> _processImage(String path) async {
    // Load the image from file
    final imgFile = File(path);
    final img.Image image = img.decodeImage(await imgFile.readAsBytes())!;

    // Get the camera preview size
    final double previewWidth = _cameraController!.value.previewSize!.width;
    final double previewHeight = _cameraController!.value.previewSize!.height;

    // Calculate focus area dimensions based on percentages
    final double focusAreaWidth = previewWidth * focusAreaWidthPercent;
    final double focusAreaHeight = previewHeight * focusAreaHeightPercent;
    final double focusAreaLeft = (previewWidth - focusAreaWidth) / 2;
    final double focusAreaTop = (previewHeight - focusAreaHeight) / 2;

    // Calculate the scale ratio
    final double scaleX = image.width / previewWidth;
    final double scaleY = image.height / previewHeight;

    // Calculate the cropping offsets and dimensions
    final int cropLeft = (focusAreaLeft * scaleX).toInt();
    final int cropTop = (focusAreaTop * scaleY).toInt();
    final int cropWidth = (focusAreaWidth * scaleX).toInt();
    final int cropHeight = (focusAreaHeight * scaleY).toInt();

    // Crop the image
    final img.Image croppedImage = img.copyCrop(image, cropLeft, cropTop, cropWidth, cropHeight);

    // Save the cropped image to a new file
    final Directory tempDir = await getTemporaryDirectory();
    final String croppedImagePath = join(tempDir.path, 'cropped_${DateTime.now()}.png');
    final File croppedImageFile = File(croppedImagePath);
    await croppedImageFile.writeAsBytes(img.encodePng(croppedImage));

    // Perform text recognition on the cropped image
    final inputImage = InputImage.fromFilePath(croppedImagePath);
    final textRecognizer = TextRecognizer();
    final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

    // Get the full text from the recognized text blocks
    String scannedText = recognizedText.text;

    // Update the text field with the full scanned text
    setState(() {
      _textController.text = scannedText;
    });

    // Add the scanned text to the stream as well
    controller.add(scannedText);
  }


  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).viewPadding.top;

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double previewWidth = constraints.maxWidth;
          final double previewHeight = constraints.maxHeight;

          // Calculate focus area dimensions and position
          final double focusAreaWidth = previewWidth * focusAreaWidthPercent;
          final double focusAreaHeight = previewHeight * focusAreaHeightPercent;
          final double focusAreaLeft = (previewWidth - focusAreaWidth) / 2;
          final double focusAreaTop = (previewHeight - focusAreaHeight) / 2 - 65;

          return Stack(
            children: [
              CameraPreview(_cameraController!),
              CustomPaint(
                painter: FocusAreaPainter(
                  focusAreaWidth: focusAreaWidth,
                  focusAreaHeight: focusAreaHeight,
                  focusAreaTop: focusAreaTop,
                  focusAreaLeft: focusAreaLeft,
                ),
              ),
              Column(
                children: [
                  SizedBox(
                    height: statusBarHeight + kToolbarHeight,
                    child: AppBar(
                      title: const Text('GOODYEAR TYRE SCANNER'),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            decoration: const InputDecoration(
                              hintText: 'Type here or use speech-to-text',
                              hintStyle: TextStyle(color: Colors.white54),
                            ),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        IconButton(
                          icon: Icon(_isListening ? Icons.mic : Icons.mic_none, color: Colors.white),
                          onPressed: _listen,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SingleChildScrollView(
                        child: Container(
                          color: Colors.black,
                          child: StreamBuilder<String>(
                            stream: controller.stream,
                            builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
                              return Text(
                                snapshot.data ?? '',
                                style: const TextStyle(color: Colors.white),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: IconButton(
                      onPressed: _captureImage,
                      iconSize: 50,
                      icon: const Icon(Icons.camera, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class FocusAreaPainter extends CustomPainter {
  final double focusAreaWidth;
  final double focusAreaHeight;
  final double focusAreaTop;
  final double focusAreaLeft;

  FocusAreaPainter({
    required this.focusAreaWidth,
    required this.focusAreaHeight,
    required this.focusAreaTop,
    required this.focusAreaLeft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRect(
      Rect.fromLTWH(focusAreaLeft, focusAreaTop, focusAreaWidth, focusAreaHeight),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
