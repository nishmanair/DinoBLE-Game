#include <Arduino_LSM9DS1.h> // IMU sensor
#include <TensorFlowLite.h> // Core TFLite library
#include <tensorflow/lite/micro/micro_interpreter.h> // For microcontroller inference
#include <tensorflow/lite/micro/all_ops_resolver.h> // All supported TFLite ops
#include <tensorflow/lite/schema/schema_generated.h> // Model schema
#include "model.h"  // Include converted TinyML model in .h format
#include <ArduinoBLE.h> // BLE communication

// Define BLE service and characteristic (2A57 = custom service, 2902 = notify characteristic)
BLEService motionService("2A57");
BLECharacteristic motionCharacteristic("2902", BLERead | BLENotify, 1);  // Send 1 byte

// Number of samples to collect for mean/std calculation
const int sample_count = 200;
float mean_ax = 0, mean_ay = 0, mean_az = 0;
float std_ax = 0, std_ay = 0, std_az = 0;
// Arrays to store samples and stats
float ax_samples[sample_count];
float ay_samples[sample_count];
float az_samples[sample_count];

const int ledPin = LED_BUILTIN; // Use built-in LED to indicate connection status

// TensorFlow Lite Micro interpreter setup
constexpr int kTensorArenaSize = 2 * 1024; // Memory buffer size
uint8_t tensor_arena[kTensorArenaSize];    // Arena for tensors
tflite::MicroInterpreter* interpreter;     // Interpreter instance
TfLiteTensor* input;                       // Model input tensor
TfLiteTensor* output;                      // Model output tensor

void setup() {
    Serial.begin(115200);
    pinMode(ledPin, OUTPUT);
    digitalWrite(ledPin, LOW);  // LED off initially
    // Initialize IMU
    if (!IMU.begin()) {
        Serial.println("IMU failed!");
        while (1);
    }
    // Initialize BLE
    if (!BLE.begin()) {
        Serial.println("BLE failed!");
        while (1);
    }
    // Setup BLE service and advertise
    BLE.setLocalName("DinoController");
    BLE.setAdvertisedService(motionService);
    motionService.addCharacteristic(motionCharacteristic);
    BLE.addService(motionService);
    motionCharacteristic.writeValue((uint8_t)0);  // Default value
    BLE.advertise();

    // === TinyML: Load model and set up interpreter ===
    const tflite::Model* model = tflite::GetModel(model_tflite);
    static tflite::AllOpsResolver resolver;
    static tflite::MicroInterpreter static_interpreter(model, resolver, tensor_arena, kTensorArenaSize);
    interpreter = &static_interpreter;
    
    // Allocate tensors for inference
    TfLiteStatus allocate_status = interpreter->AllocateTensors();
    if (allocate_status != kTfLiteOk) {
        Serial.println("Tensor allocation failed!");
        while (1);
    }
    // === Calibration: collect samples to calculate mean and std ===
    Serial.println("Calculating mean of ax, ay, az...");
    for (int i = 0; i < sample_count; i++) {
      float ax, ay, az;
      if (IMU.accelerationAvailable()) {
          IMU.readAcceleration(ax, ay, az);
          ax_samples[i] = ax;
          ay_samples[i] = ay;
          az_samples[i] = az;
          delay(10);  // sample rate
        }
      }
    // Calculate mean for each axis
    float mean_ax = 0, mean_ay = 0, mean_az = 0;
    for (int i = 0; i < sample_count; i++) {
        mean_ax += ax_samples[i];
        mean_ay += ay_samples[i];
        mean_az += az_samples[i];
      }
      mean_ax /= sample_count;
      mean_ay /= sample_count;
      mean_az /= sample_count;
      // Step 3: Calculate standard deviation
      float std_ax = 0, std_ay = 0, std_az = 0;
      for (int i = 0; i < sample_count; i++) {
        std_ax += pow(ax_samples[i] - mean_ax, 2);
        std_ay += pow(ay_samples[i] - mean_ay, 2);
        std_az += pow(az_samples[i] - mean_az, 2);
      }
      // Calculate standard deviation for each axis
      std_ax = sqrt(std_ax / sample_count);
      std_ay = sqrt(std_ay / sample_count);
      std_az = sqrt(std_az / sample_count);
      // Get model input/output references
      input = interpreter->input(0);
      output = interpreter->output(0);
    Serial.println("BLE advertising... + TinyML Ready!");
}

void loop() {
    // Wait for a BLE central device to connect
    BLEDevice central = BLE.central();
    if (central) {
        Serial.print("Connected to central: ");
        Serial.println(central.address());
        digitalWrite(ledPin, HIGH);  //  Turn LED ON when connected
        while (central.connected()) {
            float ax, ay, az;
            // Check if new IMU data is available
            if (IMU.accelerationAvailable()) {
                IMU.readAcceleration(ax, ay, az);
                // === Normalize input using precomputed mean and std ===
                float epsilon = 1e-6; // Prevent divide-by-zero
                input->data.f[0] = (ax - mean_ax) / (std_ax + epsilon);
                input->data.f[1] = (ay - mean_ay) / (std_ay + epsilon);
                input->data.f[2] = (az - mean_az) / (std_az + epsilon);
                // Run inference
                TfLiteStatus invoke_status = interpreter->Invoke();
                if (invoke_status != kTfLiteOk) {
                    Serial.println("Invoke failed!");
                    continue;
                }
                // Read model output scores
                float idle_score = output->data.f[0];
                float jump_score = output->data.f[1];
                // Predict class based on higher score
                int predicted_class = jump_score > idle_score ? 1 : 0;
                // Send "1" via BLE if jump is detected
                if (predicted_class == 1) {
                    uint8_t value = 1;
                    motionCharacteristic.setValue(&value, 1);
                    Serial.print("Jump Detected.\t");
                    Serial.println("Sent 1 to flutter dino game app");
                  }
              }
            delay(100);// Small delay between predictions
        }
        digitalWrite(ledPin, LOW);  //  Turn LED OFF when disconnected
        Serial.println("Disconnected from central");
    }
}
