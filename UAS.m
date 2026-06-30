%% Langkah 1: Membaca dan Menampilkan Dua Frame Pertama
% Kegunaan: Membaca file video, mengambil dua frame pertama, mengubahnya menjadi grayscale, 
% dan menampilkannya berdampingan serta sebagai gambar komposit (anaglyph) untuk melihat visualisasi getaran awal.
filename = "shaky_car.avi";
hVideoSrc = VideoReader(filename); % Membuka file video
imgA = readFrame(hVideoSrc);       % Membaca frame pertama (Frame A)
imgA = im2gray(imgA);              % Mengubah Frame A ke grayscale
imgB = readFrame(hVideoSrc);       % Membaca frame kedua (Frame B)
imgB = im2gray(imgB);              % Mengubah Frame B ke grayscale

% Membuat citra komposit stereo anaglyph untuk melihat pergeseran antar frame
compositeImg = stereoAnaglyph(imgA,imgB); 

figure;
subplot(1,3,[1 2])
montage({imgA,imgB});
title("Frame A | Frame B");
subplot(1,3,3)
imshow(compositeImg);
title("Color composite (frame A = red,frame B = cyan)");
truesize

%% Langkah 2: Menentukan Metode Optical Flow
% Kegunaan: Menentukan algoritma tracking yang akan digunakan. 
% Anda bisa memilih "Farneback" (cepat, berbasis intensitas) atau "RAFT" (berbasis Deep Learning, lebih akurat).
flowMethod = "Farneback";
switch flowMethod
    case "Farneback"
        flowModel = opticalFlowFarneback; % Inisialisasi objek model Farneback
    case "RAFT"
        flowModel = opticalFlowRAFT;      % Inisialisasi objek model RAFT  
end 

%% Langkah 3: Mengestimasi Optical Flow Antar Frame
% Kegunaan: Melatih/menginisialisasi model pada frame pertama, lalu menghitung 
% pergeseran piksel (vektor pergerakan) dari frame A ke frame B.
estimateFlow(flowModel,imgA);         % Inisialisasi model dengan frame pertama
flow = estimateFlow(flowModel,imgB);  % Menghitung pergerakan pada frame kedua

%% Langkah 4: Visualisasi Vektor Optical Flow
% Kegunaan: Menampilkan Frame A dan menggambarkan vektor pergerakan (panah hijau) 
% untuk melihat ke mana arah pergeseran piksel akibat guncangan kamera.
figure
imshow(imgA, InitialMagnification=250)
hold on
% Menampilkan plot vektor flow dengan penyusutan (decimation) agar tidak terlalu padat
plot(flow,DecimationFactor=[5 5],ScaleFactor=2.0,Color="green");
title("Optical Flow")

%% Langkah 5: Penyaringan (Filtering) Optical Flow yang Valid
% Kegunaan: Menyaring koordinat piksel yang keluar dari batas gambar atau memiliki 
% pergerakan yang terlalu kecil (noise), sehingga menyisakan gerakan yang valid saja.
minFlowThreshold = 1; % Ambang batas pergerakan minimal (dalam piksel)

% Membuat matriks koordinat gambar
[H,W,~] = size(imgA);
[X1,Y1] = meshgrid(1:W,1:H);

% Menghitung estimasi posisi piksel baru di Image B menggunakan vektor Vx dan Vy
X2 = X1 + flow.Vx;
Y2 = Y1 + flow.Vy;

% Masking untuk menyaring koordinat yang valid dan di atas threshold
validFlow = X2>=1 & X2<=W & Y2>=1 & Y2<=H & flow.Magnitude > minFlowThreshold;

% Menampilkan area mana saja yang memiliki flow valid (overlay warna)
overlayImg = labeloverlay(imgA,validFlow);
figure
imshow(overlayImg, InitialMagnification=250)
hold on
plot(flow,DecimationFactor=[5 5],ScaleFactor=2.0,Color="green");
title("Valid Optical Flow")

%% Langkah 6: Mengumpulkan Titik-Titik Piksel yang Berpasangan (Densely Matched Points)
% Kegunaan: Mengambil koordinat piksel yang valid dari Frame A (matchedDensePtsA) 
% dan pasangannya di Frame B (matchedDensePtsB) untuk digunakan dalam estimasi transformasi geometris.
matchedDensePtsA = single([X1(validFlow), Y1(validFlow)]);
matchedDensePtsB = [X2(validFlow), Y2(validFlow)];

%% Langkah 7: Estimasi Transformasi Geometris dan Stabilisasi Awal
% Kegunaan: Menghitung matriks transformasi "rigid" (translasi & rotasi) antar dua frame 
% menggunakan titik koordinat yang berpasangan, lalu melakukan warping (pergeseran) pada Frame B agar lurus dengan Frame A.
tform = estgeotform2d(matchedDensePtsB,matchedDensePtsA,"rigid");
imgBStable = imwarp(imgB,tform,OutputView=imref2d(size(imgB)));

%% Langkah 8: Menampilkan Matriks Transformasi
% Kegunaan: Menampilkan detail angka/nilai matriks transformasi (rotasi dan translasi) ke command window.
disp(tform)

%% Langkah 9: Visualisasi Hasil Perbandingan Sebelum dan Sesudah Stabilisasi
% Kegunaan: Menampilkan perbedaan sebelum dan sesudah stabilisasi menggunakan efek stereo anaglyph. 
% Jika gambar tidak lagi berbayang merah-cyan tebal, berarti stabilisasi berhasil.
compositeImgStable = stereoAnaglyph(imgA,imgBStable);
figure
subplot(1,2,1)
imshow(compositeImg);
title("Before Stabilization")
subplot(1,2,2)
imshow(compositeImgStable)
title("After Stabilization")

%% Langkah 10: Mengembalikan Waktu Video ke Awal
% Kegunaan: Me-reset pointer pembacaan video kembali ke detik ke-0 agar video bisa diproses ulang secara penuh di dalam loop.
hVideoSrc.CurrentTime = 0; 

%% Langkah 11: Mereset Model Optical Flow
% Kegunaan: Membersihkan memori/history internal pada objek flowModel agar siap melakukan kalkulasi dari awal video.
reset(flowModel);

%% Langkah 12: Inisialisasi Variabel Frame untuk Pemrosesan Video Loop
% Kegunaan: Membaca frame pertama video, mengubahnya ke grayscale, dan menyimpannya 
% sebagai referensi awal (`prevGray` dan `prevStable`) sebelum masuk ke perulangan (loop).
prevFrame   = readFrame(hVideoSrc);
prevGray    = im2gray(prevFrame);
prevStable  = prevGray;

%% Langkah 13: Inisialisasi Awal Flow Model pada Frame Pertama Video
% Kegunaan: Melakukan "warm-up" atau pengenalan bentuk struktur frame pertama pada model optical flow.
estimateFlow(flowModel, prevGray);

%% Langkah 14: Menentukan Parameter Jarak Maksimum RANSAC
% Kegunaan: Menentukan batas toleransi jarak (dalam piksel) untuk mengidentifikasi apakah 
% suatu titik termasuk data yang benar (inlier) atau error/noise (outlier) saat perhitungan RANSAC.
ransacMaxDistance = 4;

%% Langkah 15: Menentukan Parameter Maksimum Iterasi RANSAC
% Kegunaan: Membatasi jumlah trial/percobaan algoritma RANSAC dalam mencari model transformasi terbaik 
% demi menjaga keseimbangan antara akurasi dan kecepatan komputasi.
ransacMaxNumTrials = 1000;

%% Langkah 16: Proses Loop Stabilisasi Video Keseluruhan
% Kegunaan: Melakukan proses stabilisasi frame-by-frame secara sekuensial (berurutan) hingga maksimal 80 frame.
% Langkah ini menggabungkan pencarian optical flow, eliminasi outlier dengan RANSAC, akumulasi transformasi 
% (smooth tracking menggunakan sistem time window), penyesuaian gambar (imwarp), dan menampilkan hasil real-time.
frameIndex = 2;
maxFrames = 80;
timeWindow = 10; % Ukuran jendela waktu untuk akumulasi transformasi agar pergerakan halus
figure
allTforms = cell(1,maxFrames);
allTforms{1} = rigidtform2d; % Fr ame pertama menggunakan matriks identitas (tidak berubah)

while hasFrame(hVideoSrc) && frameIndex <= maxFrames
    % 1. Membaca frame saat ini
    frame = readFrame(hVideoSrc);
    frameGray = im2gray(frame);
    
    % 2. Menghitung Dense Optical Flow dari frame sebelumnya ke frame saat ini
    flow = estimateFlow(flowModel, frameGray);
    [H,W,~] = size(frame);
    [X1,Y1] = meshgrid(1:W,1:H);
    X2 = X1 + flow.Vx;
    Y2 = Y1 + flow.Vy;
    
    % 3. Menyaring koordinat flow yang valid
    validFlow = X2>=1 & X2<=W & Y2>=1 & Y2<=H & flow.Magnitude > minFlowThreshold;
    matchedDensePtsA = single([X1(validFlow), Y1(validFlow)]);
    matchedDensePtsB = [X2(validFlow), Y2(validFlow)];    
    
    % 4. Menggunakan RANSAC untuk membuang titik noise dan mengestimasi transformasi rigid yang akurat
    tformFrame = estgeotform2d(matchedDensePtsB,matchedDensePtsA,"rigid",...
        MaxDistance=ransacMaxDistance,MaxNumTrials=ransacMaxNumTrials);
    allTforms{frameIndex} = tformFrame;
    
    % 5. Mengakumulasikan matriks transformasi berdasarkan rentang waktu (time window)
    windowSize = max(1,frameIndex - timeWindow);
    tformCumulative = rigidtform2d;
    for k = 1:windowSize
        tformCumulative.A = tformCumulative.A * allTforms{frameIndex - k + 1}.A;
    end
    
    % 6. Memperbaiki posisi frame (Warping) dengan matriks kumulatif
    frameStable = imwarp(frameGray,tformCumulative,OutputView=imref2d(size(frameGray)));
    
    % 7. Membuat visualisasi perbandingan (Sebelum vs Sesudah Stabilisasi)
    compositeImgRaw = stereoAnaglyph(prevGray,frameGray);
    compositeImgStable = stereoAnaglyph(prevStable,frameStable);
    imViz = cat(2,compositeImgRaw,compositeImgStable); % Menggabungkan gambar secara horizontal
    
    % 8. Menampilkan video hasil stabilisasi secara langsung (real-time)
    imshow(imViz, InitialMagnification=250)
    title("Before Stabilization | After Stabilization")
    drawnow
    
    % 9. Bersiap untuk iterasi frame berikutnya
    prevGray = frameGray;
    prevStable = frameStable;
    frameIndex = frameIndex + 1;
end