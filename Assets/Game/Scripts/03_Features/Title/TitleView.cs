using UnityEngine;
using UnityEngine.UI;
using DG.Tweening;
using UnityEngine.InputSystem;

public class TitleView : MonoBehaviour
{
    [SerializeField] private Button m_newGameButton;
    [SerializeField] private Button m_loadButton;
    [SerializeField] private Button m_storyTreeButton;
    [SerializeField] private Button m_encyclopediaButton;
    [SerializeField] private Button m_settingsButton;
    [SerializeField] private Button m_creditButton;
    [SerializeField] private Button m_exitButton;
    [SerializeField] private RectTransform m_focusMarker;
    [SerializeField] private Image m_backgroundImage;

    private ITitleViewModel m_viewModel;
    private ISoundService m_soundService;
    private Button[] m_menuButtons;
    private int m_currentFocusIndex = 0;

    public void Initialize(ITitleViewModel viewModel, ISoundService soundService = null)
    {
        if (viewModel == null)
        {
            return;
        }
        m_viewModel = viewModel;
        m_soundService = soundService;

        System.Collections.Generic.List<Button> activeButtons = new System.Collections.Generic.List<Button>();

        if (m_newGameButton != null)
        {
            m_newGameButton.navigation = new Navigation { mode = Navigation.Mode.None };
            activeButtons.Add(m_newGameButton);
        }
        if (m_loadButton != null)
        {
            m_loadButton.navigation = new Navigation { mode = Navigation.Mode.None };
            m_loadButton.interactable = m_viewModel.IsLoadGameActive;
            activeButtons.Add(m_loadButton);
        }
        if (m_storyTreeButton != null)
        {
            m_storyTreeButton.navigation = new Navigation { mode = Navigation.Mode.None };
            bool isStoryTreeActive = m_viewModel.IsStoryTreeActive;
            m_storyTreeButton.gameObject.SetActive(isStoryTreeActive);
            if (isStoryTreeActive)
            {
                activeButtons.Add(m_storyTreeButton);
            }
        }
        if (m_encyclopediaButton != null)
        {
            m_encyclopediaButton.navigation = new Navigation { mode = Navigation.Mode.None };
            activeButtons.Add(m_encyclopediaButton);
        }
        if (m_settingsButton != null)
        {
            m_settingsButton.navigation = new Navigation { mode = Navigation.Mode.None };
            activeButtons.Add(m_settingsButton);
        }
        if (m_creditButton != null)
        {
            m_creditButton.navigation = new Navigation { mode = Navigation.Mode.None };
            activeButtons.Add(m_creditButton);
        }
        if (m_exitButton != null)
        {
            m_exitButton.navigation = new Navigation { mode = Navigation.Mode.None };
            activeButtons.Add(m_exitButton);
        }

        m_menuButtons = activeButtons.ToArray();

        if (m_viewModel.IsLoadGameActive && m_menuButtons.Length > 1 && m_menuButtons[1] == m_loadButton)
        {
            m_currentFocusIndex = 1;
        }
        else
        {
            m_currentFocusIndex = 0;
        }

        UpdateFocusVisuals(false);
        ApplyEndingBackground();

        if (m_soundService != null)
        {
            m_soundService.PlayBGM("Title/titleSample03", 1.0f);
        }
    }

    private void Update()
    {
        if (m_menuButtons == null || m_menuButtons.Length == 0)
        {
            return;
        }

        var keyboard = Keyboard.current;
        if (keyboard == null)
        {
            for (int i = 0; i < UnityEngine.InputSystem.InputSystem.devices.Count; i++)
            {
                var device = UnityEngine.InputSystem.InputSystem.devices[i];
                if (device is Keyboard k)
                {
                    keyboard = k;
                    break;
                }
            }
        }

        if (keyboard == null)
        {
            return;
        }

        bool focusChanged = false;

        if (keyboard.upArrowKey.wasPressedThisFrame)
        {
            m_currentFocusIndex = (m_currentFocusIndex - 1 + m_menuButtons.Length) % m_menuButtons.Length;
            focusChanged = true;
        }
        else if (keyboard.downArrowKey.wasPressedThisFrame)
        {
            m_currentFocusIndex = (m_currentFocusIndex + 1) % m_menuButtons.Length;
            focusChanged = true;
        }
        else if (keyboard.enterKey.wasPressedThisFrame || keyboard.spaceKey.wasPressedThisFrame)
        {
            ExecuteFocusedMenu();
        }

        if (focusChanged)
        {
            UpdateFocusVisuals(true);
        }
    }

    private void ExecuteFocusedMenu()
    {
        if (m_menuButtons == null || m_currentFocusIndex >= m_menuButtons.Length)
        {
            return;
        }

        var focusedButton = m_menuButtons[m_currentFocusIndex];
        if (focusedButton.interactable == false)
        {
            return;
        }

        focusedButton.onClick.Invoke();
    }

    private void UpdateFocusVisuals(bool useAnimation = true)
    {
        if (m_menuButtons == null || m_menuButtons.Length == 0)
        {
            return;
        }

        for (int i = 0; i < m_menuButtons.Length; i++)
        {
            var text = m_menuButtons[i].GetComponentInChildren<TMPro.TMP_Text>();
            if (text != null)
            {
                if (i == m_currentFocusIndex)
                {
                    text.color = new Color(0.75f, 0.22f, 0.17f, 1.0f);
                }
                else
                {
                    text.color = new Color(0.05f, 0.05f, 0.06f, 1.0f);
                }
            }
        }

        if (m_focusMarker != null && m_currentFocusIndex < m_menuButtons.Length)
        {
            var targetButton = m_menuButtons[m_currentFocusIndex].GetComponent<RectTransform>();
            if (targetButton != null)
            {
                Vector3 buttonWorldPos = targetButton.position;
                Vector3 markerLocalPos = m_focusMarker.parent.InverseTransformPoint(buttonWorldPos);
                
                float calculatedY = markerLocalPos.y;
                float targetX = -130f; // 가로축 수직 정렬 마커 마진값 고정

                if (useAnimation)
                {
                    m_focusMarker.DOAnchorPos(new Vector2(targetX, calculatedY), 0.22f);
                }
                else
                {
                    m_focusMarker.anchoredPosition = new Vector2(targetX, calculatedY);
                }
            }
        }
    }

    private void ApplyEndingBackground()
    {
        if (m_backgroundImage == null || m_viewModel == null)
        {
            return;
        }

        string recentEnding = m_viewModel.RecentEndingId;
        Color targetColor = Color.white;

        if (recentEnding == "A_붕괴")
        {
            targetColor = new Color(0.56f, 0.16f, 0.13f, 1.0f);
        }
        else if (recentEnding == "B_계승")
        {
            targetColor = new Color(0.18f, 0.36f, 0.54f, 1.0f);
        }

        m_backgroundImage.DOColor(targetColor, 0.6f);
    }

    public void func_OnNewGameButtonClicked()
    {
        if (m_soundService != null)
        {
            m_soundService.PlaySFX(SoundKeys.NewGame);
        }
        if (m_viewModel != null)
        {
            m_viewModel.NewGame();
        }
    }

    public void func_OnLoadGameButtonClicked()
    {
        if (m_soundService != null)
        {
            m_soundService.PlaySFX(SoundKeys.Click);
        }
        if (m_viewModel != null)
        {
            m_viewModel.LoadGame();
        }
    }

    public void func_OnStoryTreeButtonClicked()
    {
        if (m_soundService != null)
        {
            m_soundService.PlaySFX(SoundKeys.Click);
        }
        if (m_viewModel != null)
        {
            m_viewModel.OpenStoryTree();
        }
    }

    public void func_OnEncyclopediaButtonClicked()
    {
        if (m_soundService != null)
        {
            m_soundService.PlaySFX(SoundKeys.Click);
        }
        if (m_viewModel != null)
        {
            m_viewModel.OpenEncyclopedia();
        }
    }

    public void func_OnSettingsButtonClicked()
    {
        if (m_soundService != null)
        {
            m_soundService.PlaySFX(SoundKeys.Click);
        }
        if (m_viewModel != null)
        {
            m_viewModel.OpenSettings();
        }
    }

    public void func_OnCreditsButtonClicked()
    {
        if (m_soundService != null)
        {
            m_soundService.PlaySFX(SoundKeys.Click);
        }
        if (m_viewModel != null)
        {
            m_viewModel.OpenCredits();
        }
    }

    public void func_OnQuitButtonClicked()
    {
        if (m_soundService != null)
        {
            m_soundService.PlaySFX(SoundKeys.Click);
        }
        if (m_viewModel != null)
        {
            m_viewModel.QuitGame();
        }
    }
}
