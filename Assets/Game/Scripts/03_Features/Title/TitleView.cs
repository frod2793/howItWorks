using UnityEngine;
using UnityEngine.UI;

public class TitleView : MonoBehaviour
{
    [Header("메뉴 버튼")]
    [SerializeField] private Button m_newGameButton;
    [SerializeField] private Button m_loadGameButton;
    [SerializeField] private Button m_settingsButton;
    [SerializeField] private Button m_archiveButton;

    private ITitleViewModel m_viewModel;
    private ISoundService m_soundService;

    public void Initialize(ITitleViewModel viewModel, ISoundService soundService = null)
    {
        if (viewModel == null)
        {
            return;
        }
        m_viewModel = viewModel;
        m_soundService = soundService;

        if (m_soundService != null)
        {
            m_soundService.PlayBGM("Title/titleSample03", 1.0f);
        }

        if (m_newGameButton != null)
        {
            m_newGameButton.onClick.AddListener(m_viewModel.NewGame);
        }
        if (m_loadGameButton != null)
        {
            m_loadGameButton.onClick.AddListener(m_viewModel.LoadGame);
        }
        if (m_settingsButton != null)
        {
            m_settingsButton.onClick.AddListener(m_viewModel.OpenSettings);
        }
        if (m_archiveButton != null)
        {
            m_archiveButton.onClick.AddListener(m_viewModel.OpenArchive);
        }
    }

    private void OnDestroy()
    {
        if (m_newGameButton != null)
        {
            m_newGameButton.onClick.RemoveAllListeners();
        }
        if (m_loadGameButton != null)
        {
            m_loadGameButton.onClick.RemoveAllListeners();
        }
        if (m_settingsButton != null)
        {
            m_settingsButton.onClick.RemoveAllListeners();
        }
        if (m_archiveButton != null)
        {
            m_archiveButton.onClick.RemoveAllListeners();
        }
    }
}
