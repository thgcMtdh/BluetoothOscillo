import controlP5.*;
import java.util.HashMap;
import processing.serial.*;
ControlP5 cp5;
Serial myPort;

// for input emulation
int currentSeqNum = 0;  // present sequence number
int messageFreq = 100;  // the number of message arrived per sec
int lastMessageMillis = 0;  // last message arrived time [ms]

// [IMPORTANT] constants
final int SAMPLE_RATE = 20000;  // ESP32 ADC sampling rate [sample/sec]
final int DISP_BUF_MAX = SAMPLE_RATE * 10;  // display buffer size
final int REC_BUF_MAX = SAMPLE_RATE * 10;  // record buffer size

int[] seqNums = new int[DISP_BUF_MAX];
int[] values = new int[DISP_BUF_MAX];
int latestIndex = -1;
int leftIndex = 0;
int oldestIndex = 0;

enum RunStatus{
  RUN,
  PAUSE
};
RunStatus runStatus = RunStatus.PAUSE;

ArrayList<Integer> seqNumsRec = new ArrayList<Integer>(REC_BUF_MAX*2);  // sample sequence id
ArrayList<Integer> valuesRec = new ArrayList<Integer>(REC_BUF_MAX*2);  // ADC read value [mV]
int recStartSeqNum = 0;

enum RecStatus{
  WAIT,
  REC,
  SAVE
};
RecStatus recStatus = RecStatus.WAIT;

final int GRID_NUM = 8;  // must be even
float horizontalWidth = 80.0;  // time between left and right [sec]
float horizontalOffset = 0.0;  // horizontal offset. shift to right when positive [sec]
float verticalWidth = 800.0;  // vertical range between bottom and top [mV]
float verticalOffset = 0.0;  // vertical offset. shift upward when positive
int graphWidth = 0;
int graphHeight = 0;

DropdownList dl0;  // horizontal scale
DropdownList dl1;  // vertical scale
Knob knob0;  // horizontal postition
Knob knob1;  // vertical position
Button bt0;  // run/pause
Button bt4;  // record button
Button bt5;  // stop button
String[] dl0Items = {"1ms/div", "2.5ms/div", "5ms/div", "10ms/div", "25ms/div", "50ms/div", "100ms/div", "250ms/div",};
String[] dl1Items = {"100mV/div", "250mV/diV", "500mV/div", "1V/div"};

void setup() {
  size(1200, 700);
  cp5 = new ControlP5(this);
  graphWidth = width - 200;
  graphHeight = height;
  background(100,100,120);
  
  // run/pause button
  bt0 = cp5.addButton("runPause");
  bt0.setLabel("RUN/PAUSE");
  bt0.setPosition(graphWidth+10, 10);
  bt0.setFont(createFont("Consolas", 16));
  bt0.setSize(80,25);
  
  // horizontal position knob
  knob0 = cp5.addKnob("horizontalPosition");
  knob0.setRange(-5, 5);
  knob0.setValue(0);
  knob0.setPosition(graphWidth+120, 90);
  knob0.setRadius(30);
  knob0.setLabelVisible(false);
  knob0.setDragDirection(Knob.VERTICAL);
  knob0.setViewStyle(Knob.ELLIPSE);
  knob0.setNumberOfTickMarks(10000);
  knob0.hideTickMarks();
  knob0.snapToTickMarks(true);
  
  // horizontal scale
  dl0 = cp5.addDropdownList("horizontalScale");
  dl0.setPosition(graphWidth+20, 180);
  dl0.setSize(160,160);
  dl0.setBarHeight(25);
  dl0.setItemHeight(25);
  dl0.setFont(createFont("Consolas", 16));
  dl0.setLabel("Scale");
  dl0.addItems(dl0Items);
  dl0.setValue(0);
  dl0.close();
  
  // vertical scale
  dl1 = cp5.addDropdownList("verticalScale");
  dl1.setPosition(graphWidth+20, 390);
  dl1.setSize(160,160);
  dl1.setBarHeight(25);
  dl1.setItemHeight(25);
  dl1.setFont(createFont("Consolas", 16));
  dl1.setLabel("Scale");
  dl1.addItems(dl1Items);
  dl1.setValue(0);
  dl1.close();
  
  // vertical postion knob
  knob1 = cp5.addKnob("verticalPosition");
  knob1.setRange(-5, 5);
  knob1.setValue(0);
  knob1.setPosition(graphWidth+120, 300);
  knob1.setRadius(30);
  knob1.setLabelVisible(false);
  knob1.setDragDirection(Knob.VERTICAL);
  knob1.setViewStyle(Knob.ELLIPSE);
  knob1.setNumberOfTickMarks(10000);
  knob1.hideTickMarks();
  knob1.snapToTickMarks(true);
  
  // rec button
  bt4 = cp5.addButton("recStart");
  bt4.setLabel("REC");
  bt4.setPosition(graphWidth+10, graphHeight-70);
  bt4.setFont(createFont("Consolas", 16));
  bt4.setSize(80,25);
  
  // stop button
  bt5 = cp5.addButton("recStop");
  bt5.setLabel("STOP");
  bt5.setPosition(graphWidth+110, graphHeight-70);
  bt4.setFont(createFont("Consolas", 16));
  bt5.setSize(80,25);
}

void draw() {    
  // control area background
  background(200, 200, 200);
  stroke(200,200,200);
  strokeWeight(0);
  fill(150,150,150);
  rect(graphWidth+10, 50, 180, 170);  // horizontal background
  rect(graphWidth+10, 260, 180, 170);  // vertical background
  fill(120,120,120);
  rect(graphWidth+10, 50, 180, 30);  // horizontal text background
  rect(graphWidth+10, 260, 180, 30);  // vertical text background
  fill(255,255,255);
  textSize(16);
  textAlign(LEFT);
  text("Horizontal", graphWidth+20, 70);
  text("Position", graphWidth+20, 100);
  text(convertFloatToSIString(horizontalOffset) + "s", graphWidth+30, 130);
  text("Scale", graphWidth+20, 170);
  text("Vertical", graphWidth+20, 280);
  text("Position", graphWidth+20, 310);
  text(convertFloatToSIString(verticalOffset) + "V", graphWidth+30, 340);
  text("Scale", graphWidth+20, 380);
  fill(222,202,99);
  rect(graphWidth+10, 290, 5, 140);  // vertical 1 line color
  
  // recording status text
  fill(20, 20, 20);
  switch (recStatus) {
    case WAIT:
      text("Press REC to record", graphWidth+10, graphHeight-20);
      break;
    case REC:
      text("Recording... (" + String.valueOf(valuesRec.size()) + ")" , graphWidth+10, graphHeight-20);
      break;
    case SAVE:
      text("Saving...", graphWidth+10, graphHeight-20);
      break;
  }
  
  // input data emulation
  String receivedText = "";
  if (millis() - lastMessageMillis > 1000 / messageFreq) {
    lastMessageMillis = millis();
    String seqNumsText = "[";
    String valuesText = "[";
    int samplePerMessage = SAMPLE_RATE / messageFreq;
    for (int i=0; i<samplePerMessage; i++) {
      seqNumsText += String.valueOf(currentSeqNum);
      valuesText += String.valueOf(200*sin(4.0*PI*currentSeqNum/SAMPLE_RATE));
      if (i < samplePerMessage - 1) {
        seqNumsText += ",";
        valuesText += ",";
      } else {
        seqNumsText += "]";
        valuesText += "]";
      }
      currentSeqNum += 1;
    }
    receivedText += "{\"seqNums\": ";
    receivedText += seqNumsText;
    receivedText += ", \"values\": ";
    receivedText += valuesText;
    receivedText += "}";
  }
  
  // parse received text
  if (receivedText != "") {
    JSONObject body = parseJSONObject(receivedText);
    if (body != null) {
      int size = body.getJSONArray("values").size();
      
      // get data from body
      for (int i=0; i<size; i++) {
        int seqNum = body.getJSONArray("seqNums").getInt(i);
        int value = body.getJSONArray("values").getInt(i);
        
        // add data to display buffer
        if (runStatus == RunStatus.RUN) {
          latestIndex = (latestIndex + 1) % values.length;
          seqNums[latestIndex] = seqNum;
          values[latestIndex] = value;
        }
        
        // if REC mode, also add data to the recording buffer
        if (recStatus == RecStatus.REC) {
          if (valuesRec.size() < REC_BUF_MAX) {
            seqNumsRec.add(seqNum);
            valuesRec.add(value);
          } else {
            recStop();
          }
        }
      }
      
      // save recording buffer
      if (recStatus == RecStatus.SAVE) {
        String fileName= nf(year(), 4) + nf(month(), 2) + nf(day(), 2) + nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2) + ".csv";
        PrintWriter writer = createWriter(fileName);
        for (int i=0; i<valuesRec.size(); i++) {
          writer.print(String.valueOf((float)(seqNumsRec.get(i) - recStartSeqNum) / SAMPLE_RATE));  // convert to time[s]
          writer.print(",");
          writer.println(String.valueOf(valuesRec.get(i)));
        }
        writer.flush();
        writer.close();
        seqNumsRec.clear();
        valuesRec.clear();
        recStartSeqNum = 0;
        recStatus = RecStatus.WAIT;
      }
    }
  }
  
  // graph area background
  fill(20, 20, 20);
  rect(0, 0, graphWidth, graphHeight);
   
  // graph grid (x,y)
  strokeWeight(3);
  stroke(64,64,64);
  line((float)graphWidth / 2, 0, (float)graphWidth / 2, graphHeight);  // vertical center line
  line(0, (float)graphHeight / 2, graphWidth-3, (float)graphHeight / 2);  // horizontal center line
  
  // graph grid (8x8)
  strokeWeight(1);
  for (int i=0; i<GRID_NUM-1; i++) {
    if (i != GRID_NUM / 2 - 1) {
      line((float)graphWidth / GRID_NUM * (i+1), 0, (float)graphWidth / GRID_NUM * (i+1), graphHeight);  // vertical line
      line(0, (float)graphHeight / GRID_NUM * (i+1), graphWidth-1, (float)graphHeight / GRID_NUM * (i+1));  // horizontal line
    }
  }
  
  // calculate index range to draw graph
  int horizontalSampleNum = int(horizontalWidth * SAMPLE_RATE);
  oldestIndex = latestIndex - horizontalSampleNum;
  if (oldestIndex < 0) { oldestIndex = DISP_BUF_MAX + oldestIndex; }
  
  if ((oldestIndex < latestIndex && (leftIndex < oldestIndex || latestIndex < leftIndex)) ||
      (latestIndex < oldestIndex && (latestIndex < leftIndex && leftIndex < oldestIndex))) {
    leftIndex = latestIndex;
  } 
  
  // draw graph
  stroke(222, 202, 99);
  
  int i = leftIndex;
  while (i != latestIndex) {  // leftIndex -> latestIndex
    if (i + 1 < DISP_BUF_MAX) {
      int x1 = i - leftIndex;
      int x2 = i + 1 - leftIndex;
      if (x1 < 0) { x1 = DISP_BUF_MAX + x1; }  // make sure x1 > 0
      if (x2 < 0) { x2 = DISP_BUF_MAX + x2; }  // make sure x2 > 0
      line(
        convertX((float)x1 / SAMPLE_RATE), convertY((float)values[i] / 1000),
        convertX((float)x2 / SAMPLE_RATE), convertY((float)values[i + 1] / 1000)
      );
    }
    i += 1;
    if (i >= DISP_BUF_MAX) {
      i = 0;
    }
  }
  
  i = leftIndex;
  while (i != oldestIndex) {  // leftIndex -> oldestIndex (draw by right to left order)
    if (i > 0) {
      int dis1 = leftIndex - i;  // distance between i to leftIndex
      int dis2 = leftIndex - (i - 1);  // distance between i-1 to leftIndex
      if (dis1 < 0) { dis1 = DISP_BUF_MAX + dis1; }  // make sure x1 > 0
      if (dis2 < 0) { dis2 = DISP_BUF_MAX + dis2; }  // make sure x2 > 0
      int x1 = horizontalSampleNum - dis1;
      int x2 = horizontalSampleNum - dis2;
      
      line(
        convertX((float)x1 / SAMPLE_RATE), convertY((float)values[i] / 1000),
        convertX((float)x2 / SAMPLE_RATE), convertY((float)values[i - 1] / 1000)
      );
    }
    i -= 1;
    if (i < 0) {
      i = DISP_BUF_MAX - 1;
    }
  }
}

float convertX(float time) {
  return (time + horizontalOffset) / horizontalWidth * graphWidth;
}

float convertY(float value) {
  return graphHeight / 2 - (value + verticalOffset) / verticalWidth * graphHeight;
}

void runPause() {
  if (runStatus == RunStatus.RUN) {
    // pause
    runStatus = RunStatus.PAUSE;
    
  } else {
    // initialize
    for (int i=0; i<values.length; i++) {
      seqNums[i] = 0;
      values[i] = 0;
    }
    latestIndex = -1;
    leftIndex = 0;
    oldestIndex = 0;
    // restart
    runStatus = RunStatus.RUN;
  }
}

void recStart() {
  if (recStatus == RecStatus.WAIT) {
    recStartSeqNum = seqNums[latestIndex]+ 1;
    recStatus = RecStatus.REC;
  }
}

void recStop() {
  if (recStatus == RecStatus.REC) {
    recStatus = RecStatus.SAVE;
  }
}

void horizontalScale() {
  String selected = dl0Items[int(dl0.getValue())];  // get selected text
  selected = selected.substring(0, selected.length() - 5);  // remove "s/div"
  float selectedValue = convertSIPrefixNumber(selected);
  horizontalWidth = GRID_NUM * selectedValue;
}

void horizontalPosition() {
  horizontalOffset = knob0.getValue();
}

void verticalScale() {
  String selected = dl1Items[int(dl1.getValue())];  // get selected text
  selected = selected.substring(0, selected.length() - 5);  // remove "V/div"
  float selectedValue = convertSIPrefixNumber(selected);
  verticalWidth = GRID_NUM * selectedValue;
}

void verticalPosition() {
  verticalOffset = knob1.getValue();
}

// convert a number with SI prefix (e.g. "100m") into float
float convertSIPrefixNumber(String str) {
  char siPrefix = str.charAt(str.length() - 1);  // last 1 charcter
  float factor = 1.0;
  if (siPrefix == 'k') {
    factor = 1000.0;
  } else if (siPrefix == 'm') {
    factor = 1.0 / 1000;
  } else if (siPrefix == 'u') {
    factor = 1.0 / 1000 / 1000;
  } else if (siPrefix == 'n') {
    factor = 1.0 / 1000 / 1000 / 1000;
  }
  if (factor == 1.0) {
    float number = float(str);  // convert input str into int because no prefix
    return number;
  } else {
    float number = float(str.substring(0, str.length() - 1));  // delete last 1 character
    return factor * number;
  }
}

// convert a float number into string with SI prefix (e.g. "100m")
String convertFloatToSIString(float number) {
  if (abs(number) >= 0.9999) {
    return nf(number, 1, 2);
  } else if (abs(number) >= 0.9999e-3) {
    return nf(number*1e3, 1, 1) + "m";
  } else if (abs(number) >= 0.9999e-6) {
    return nf(number*1e6, 1, 1) + "u";
  } else {
    return "0";
  }
}
