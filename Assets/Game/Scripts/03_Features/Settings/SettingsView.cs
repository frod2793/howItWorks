using UnityEngine;
using UnityEngine.UI;
using TMPro;

namespace Features.Settings
{
    public class SettingsView : MonoBehaviour
    {
        [SerializeField] private GameObject m_settingsPanel;

        [Header("사이드바 탭")]
        [SerializeField] private Button m_audioTabButton;
        [SerializeField] private Button m_textTabButton;
        [SerializeField] private Button m_displayTabButton;
        [SerializeField] private Button m_accessibilityTabButton;
        [SerializeField] private Button m_saveTabButton;
        [SerializeField] private Button m_inputTabButton;

        [Header("콘텐츠 패널")]
        [SerializeField] private GameObject m_audioPanel;
        [SerializeField] private GameObject m_textPanel;
        [SerializeField] private GameObject m_displayPanel;
        [SerializeField] private GameObject m_accessibilityPanel;
        [SerializeField] private GameObject m_savePanel;
        [SerializeField] private GameObject m_inputPanel;

        [Header("오디오 UI 요소")]
        [SerializeField] private Slider m_masterVolumeSlider;
        [SerializeField] private Slider m_bgmVolumeSlider;
        [SerializeField] private Slider m_sfxVolumeSlider;
        [SerializeField] private Slider m_voiceVolumeSlider;
        [SerializeField] private Toggle m_muteOnFocusLostToggle;
        [SerializeField] private TMP_Dropdown m_outputDeviceDropdown;
        [SerializeField] private TMP_Text m_masterVolumeValText;
        [SerializeField] private TMP_Text m_bgmVolumeValText;
        [SerializeField] private TMP_Text m_sfxVolumeValText;
        [SerializeField] private TMP_Text m_voiceVolumeValText;

        [Header("하단 액션 버튼")]
        [SerializeField] private Button m_restoreDefaultButton;
        [SerializeField] private Button m_cancelButton;
        [SerializeField] private Button m_applyButton;

        private ISettingsViewModel m_viewModel;

        public void Initialize(ISettingsViewModel viewModel)
        {
            if (viewModel == null)
            {
                return;
            }
            m_viewModel = viewModel;

            m_viewModel.OnStateChanged += UpdateUIValues;
            m_viewModel.OnCloseRequested += func_Close;

            SetupButtonListeners();
            SetupSliderListeners();

            UpdateUIValues();
            func_OnAudioTabButtonClicked();
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnStateChanged -= UpdateUIValues;
                m_viewModel.OnCloseRequested -= func_Close;
            }
        }

        private void SetupButtonListeners()
        {
            if (m_audioTabButton != null)
            {
                m_audioTabButton.onClick.RemoveAllListeners();
                m_audioTabButton.onClick.AddListener(func_OnAudioTabButtonClicked);
            }
            if (m_textTabButton != null)
            {
                m_textTabButton.onClick.RemoveAllListeners();
                m_textTabButton.onClick.AddListener(func_OnTextTabButtonClicked);
            }
            if (m_displayTabButton != null)
            {
                m_displayTabButton.onClick.RemoveAllListeners();
                m_displayTabButton.onClick.AddListener(func_OnDisplayTabButtonClicked);
            }
            if (m_accessibilityTabButton != null)
            {
                m_accessibilityTabButton.onClick.RemoveAllListeners();
                m_accessibilityTabButton.onClick.AddListener(func_OnAccessibilityTabButtonClicked);
            }
            if (m_saveTabButton != null)
            {
                m_saveTabButton.onClick.RemoveAllListeners();
                m_saveTabButton.onClick.AddListener(func_OnSaveTabButtonClicked);
            }
            if (m_inputTabButton != null)
            {
                m_inputTabButton.onClick.RemoveAllListeners();
                m_inputTabButton.onClick.AddListener(func_OnInputTabButtonClicked);
            }

            if (m_restoreDefaultButton != null)
            {
                m_restoreDefaultButton.onClick.RemoveAllListeners();
                m_restoreDefaultButton.onClick.AddListener(func_OnRestoreDefaultButtonClicked);
            }
            if (m_cancelButton != null)
            {
                m_cancelButton.onClick.RemoveAllListeners();
                m_cancelButton.onClick.AddListener(func_OnCancelButtonClicked);
            }
            if (m_applyButton != null)
            {
                m_applyButton.onClick.RemoveAllListeners();
                m_applyButton.onClick.AddListener(func_OnApplyButtonClicked);
            }
        }

        private void SetupSliderListeners()
        {
            if (m_masterVolumeSlider != null)
            {
                m_masterVolumeSlider.onValueChanged.RemoveAllListeners();
                m_masterVolumeSlider.onValueChanged.AddListener(func_OnMasterVolumeSliderChanged);
            }
            if (m_bgmVolumeSlider != null)
            {
                m_bgmVolumeSlider.onValueChanged.RemoveAllListeners();
                m_bgmVolumeSlider.onValueChanged.AddListener(func_OnBGMVolumeSliderChanged);
            }
            if (m_sfxVolumeSlider != null)
            {
                m_sfxVolumeSlider.onValueChanged.RemoveAllListeners();
                m_sfxVolumeSlider.onValueChanged.AddListener(func_OnSFXVolumeSliderChanged);
            }
            if (m_voiceVolumeSlider != null)
            {
                m_voiceVolumeSlider.onValueChanged.RemoveAllListeners();
                m_voiceVolumeSlider.onValueChanged.AddListener(func_OnVoiceVolumeSliderChanged);
            }
            if (m_muteOnFocusLostToggle != null)
            {
                m_muteOnFocusLostToggle.onValueChanged.RemoveAllListeners();
                m_muteOnFocusLostToggle.onValueChanged.AddListener(func_OnMuteOnFocusLostChanged);
            }
        }

        private void UpdateUIValues()
        {
            if (m_viewModel == null)
            {
                return;
            }

            if (m_masterVolumeSlider != null)
            {
                m_masterVolumeSlider.SetValueWithoutNotify(m_viewModel.MasterVolume * 100f);
            }
            if (m_bgmVolumeSlider != null)
            {
                m_bgmVolumeSlider.SetValueWithoutNotify(m_viewModel.BGMVolume * 100f);
            }
            if (m_sfxVolumeSlider != null)
            {
                m_sfxVolumeSlider.SetValueWithoutNotify(m_viewModel.SFXVolume * 100f);
            }
            if (m_voiceVolumeSlider != null)
            {
                m_voiceVolumeSlider.SetValueWithoutNotify(m_viewModel.VoiceVolume * 100f);
            }
            if (m_muteOnFocusLostToggle != null)
            {
                m_muteOnFocusLostToggle.SetIsOnWithoutNotify(m_viewModel.MuteOnFocusLost);
            }

            if (m_masterVolumeValText != null)
            {
                m_masterVolumeValText.text = Mathf.RoundToInt(m_viewModel.MasterVolume * 100f).ToString();
            }
            if (m_bgmVolumeValText != null)
            {
                m_bgmVolumeValText.text = Mathf.RoundToInt(m_viewModel.BGMVolume * 100f).ToString();
            }
            if (m_sfxVolumeValText != null)
            {
                m_sfxVolumeValText.text = Mathf.RoundToInt(m_viewModel.SFXVolume * 100f).ToString();
            }
            if (m_voiceVolumeValText != null)
            {
                m_voiceVolumeValText.text = Mathf.RoundToInt(m_viewModel.VoiceVolume * 100f).ToString();
            }
        }

        public void func_OnAudioTabButtonClicked()
        {
            SwitchTab(0);
        }

        public void func_OnTextTabButtonClicked()
        {
            SwitchTab(1);
        }

        public void func_OnDisplayTabButtonClicked()
        {
            SwitchTab(2);
        }

        public void func_OnAccessibilityTabButtonClicked()
        {
            SwitchTab(3);
        }

        public void func_OnSaveTabButtonClicked()
        {
            SwitchTab(4);
        }

        public void func_OnInputTabButtonClicked()
        {
            SwitchTab(5);
        }

        public void func_OnMasterVolumeSliderChanged(float value)
        {
            if (m_viewModel != null)
            {
                m_viewModel.MasterVolume = value / 100f;
            }
        }

        public void func_OnBGMVolumeSliderChanged(float value)
        {
            if (m_viewModel != null)
            {
                m_viewModel.BGMVolume = value / 100f;
            }
        }

        public void func_OnSFXVolumeSliderChanged(float value)
        {
            if (m_viewModel != null)
            {
                m_viewModel.SFXVolume = value / 100f;
            }
        }

        public void func_OnVoiceVolumeSliderChanged(float value)
        {
            if (m_viewModel != null)
            {
                m_viewModel.VoiceVolume = value / 100f;
            }
        }

        public void func_OnMuteOnFocusLostChanged(bool value)
        {
            if (m_viewModel != null)
            {
                m_viewModel.MuteOnFocusLost = value;
            }
        }

        public void func_OnRestoreDefaultButtonClicked()
        {
            if (m_viewModel != null)
            {
                m_viewModel.ResetToDefault();
            }
        }

        public void func_OnCancelButtonClicked()
        {
            if (m_viewModel != null)
            {
                m_viewModel.CancelSettings();
            }
        }

        public void func_OnApplyButtonClicked()
        {
            if (m_viewModel != null)
            {
                m_viewModel.ApplySettings();
            }
        }

        private void SwitchTab(int tabIndex)
        {
            if (m_audioPanel != null)
            {
                m_audioPanel.SetActive(tabIndex == 0);
            }
            if (m_textPanel != null)
            {
                m_textPanel.SetActive(tabIndex == 1);
            }
            if (m_displayPanel != null)
            {
                m_displayPanel.SetActive(tabIndex == 2);
            }
            if (m_accessibilityPanel != null)
            {
                m_accessibilityPanel.SetActive(tabIndex == 3);
            }
            if (m_savePanel != null)
            {
                m_savePanel.SetActive(tabIndex == 4);
            }
            if (m_inputPanel != null)
            {
                m_inputPanel.SetActive(tabIndex == 5);
            }
        }

        public void func_Open()
        {
            if (m_settingsPanel != null)
            {
                m_settingsPanel.SetActive(true);
            }
        }

        public void func_Close()
        {
            if (m_settingsPanel != null)
            {
                m_settingsPanel.SetActive(false);
            }
        }
    }
}
