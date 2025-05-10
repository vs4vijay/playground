// #![cfg_attr(not(debug_assertions), windows_subsystem = "windows")] // hide console window on Windows in release

// use eframe::egui;
use egui::Ui;

fn main() {
    let mut name = String::new();
    let mut age = 0;

    let mut ui = Ui::new();

    println!("Hello from Vizard!");

    ui.heading("My egui Application");
    
    // Wrap the horizontal layout in a container to constrain its width
    ui.horizontal(|ui| {
        ui.label("Your name: ");
        ui.text_edit_singleline(&mut name);
    }).container_width(200.0);

     // Add slider and button to increment age
     ui.add(egui::Slider::new(&mut age, 0..=120).text("Age"));
     if ui.button("Click each year").clicked() {
         age += 1;
     }

     // Display greeting with formatted variables
     let greeting = format!("Hello '{}', Age {}", name, age);
     ui.label(greeting);

}


// fn main() -> Result<(), eframe::Error> {
//     // env_logger::init(); // Log to stderr (if you run with `RUST_LOG=debug`).

//     let options = eframe::NativeOptions {
//         initial_window_size: Some(egui::vec2(320.0, 240.0)),
//         ..Default::default()
//     };

//     // Our application state:
//     let mut name = "Arthur".to_owned();
//     let mut age = 42;

//     eframe::run_simple_native("My egui App", options, move |ctx, _frame| {
//         egui::CentralPanel::default().show(ctx, |ui| {
//             ui.heading("My egui Application");
//             ui.horizontal(|ui| {
//                 let name_label = ui.label("Your name: ");
//                 ui.text_edit_singleline(&mut name)
//                     .labelled_by(name_label.id);
//             });
//             ui.add(egui::Slider::new(&mut age, 0..=120).text("age"));
//             if ui.button("Click each year").clicked() {
//                 age += 1;
//             }
//             ui.label(format!("Hello '{}', age {}", name, age));
//         });
//     })
// }
