import { createRoot } from "react-dom/client";
import App from "./App";
import SynthDebug from "./SynthDebug";
import {getCurrentWindow} from '@tauri-apps/api/window';
import "./style.css";
createRoot(document.getElementById("root")!).render(getCurrentWindow().label==='synth'?<SynthDebug/>:<App />);
