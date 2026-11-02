import { createRoot } from "react-dom/client";
import App from "./App";
import SynthDebug from "./SynthDebug";
import VoiceStudio from "./VoiceStudio";
import {getCurrentWindow} from '@tauri-apps/api/window';
import "./style.css";
const label = getCurrentWindow().label;
createRoot(document.getElementById("root")!).render(label==='voice-engine'?<VoiceStudio/>:label==='synth'?<SynthDebug/>:<App />);
