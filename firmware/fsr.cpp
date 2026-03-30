const int fsrPin = A0;
int fsrValue = 0;
int currentSeconds = 0;

const int maxSeconds = 25;
const int interval = 200;

const double stdDev = 0.68;

const int elements = maxSeconds * (1000 / interval);
const int middle = (elements - 1) / 2;

const int lower = middle - (int)((stdDev / 2.0) * elements);
const int upper = middle + (int)((stdDev / 2.0) * elements) + 1;

int index = 0;
int measurements[elements] = {0};

float avg(int arr[], int lower, int upper)
{
  float sum = 0.0;
  int elems = upper - lower;

  if (elems <= 0) return 0;

  for (int i = lower; i < upper; i++)
  {
    sum += arr[i];
  }
  return sum / elems;
}

void setup() {
  Serial.begin(9600);
  Serial.println("Program has started.");
}

void loop() {
  float average;

  fsrValue = analogRead(fsrPin);
  currentSeconds = millis() / 1000;

  if (index < elements) {
    measurements[index] = fsrValue;
    index++;
  }

  delay(interval);

  if (currentSeconds >= maxSeconds)
  {
    average = avg(measurements, lower, upper);
    Serial.println(average);

    while (true); // stop program
  }
}