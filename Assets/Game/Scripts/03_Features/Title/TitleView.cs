using UnityEngine;
using UnityEngine.UI;

public class TitleView : MonoBehaviour
{
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
    }

    public void func_OnNewGameButtonClicked()
    {
        if (m_viewModel != null)
        {
            m_viewModel.NewGame();
        }
    }

    public void func_OnLoadGameButtonClicked()
    {
        if (m_viewModel != null)
        {
            m_viewModel.LoadGame();
        }
    }

    public void func_OnStoryTreeButtonClicked()
    {
        if (m_viewModel != null)
        {
            m_viewModel.OpenStoryTree();
        }
    }

    public void func_OnArchiveButtonClicked()
    {
        if (m_viewModel != null)
        {
            m_viewModel.OpenArchive();
        }
    }

    public void func_OnSettingsButtonClicked()
    {
        if (m_viewModel != null)
        {
            m_viewModel.OpenSettings();
        }
    }

    public void func_OnCreditsButtonClicked()
    {
        if (m_viewModel != null)
        {
            m_viewModel.OpenCredits();
        }
    }

    public void func_OnQuitButtonClicked()
    {
        if (m_viewModel != null)
        {
            m_viewModel.QuitGame();
        }
    }
}
