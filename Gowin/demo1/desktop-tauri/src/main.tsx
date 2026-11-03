import React from 'react';
import ReactDOM from 'react-dom/client';
import '@fontsource-variable/geist';
import '@fontsource-variable/jetbrains-mono';
import App from './App';
import './styles.css';
import './unified-studio.css';
import {configureMergedStudio} from '../../../demo_test/desktop-tauri/src/voice-api';
configureMergedStudio();

ReactDOM.createRoot(document.getElementById('root')!).render(<React.StrictMode><App/></React.StrictMode>);
