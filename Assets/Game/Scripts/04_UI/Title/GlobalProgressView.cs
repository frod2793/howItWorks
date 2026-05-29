using UnityEngine;
using TMPro;

public class GlobalProgressView : MonoBehaviour
{
    [SerializeField] private TMP_Text m_headerText;
    [SerializeField] private TMP_Text m_playTimeText;
    [SerializeField] private TMP_Text m_endingText;
    [SerializeField] private TMP_Text m_subplotText;

    private GlobalProgressViewModel m_viewModel;

    private void Start()
    {
        if (m_viewModel == null)
        {
            GlobalProgressDTO mockDTO = new GlobalProgressDTO
            {
                PlayCount = 1,
                AccumulatedTime = 9000f,
                UnlockedEndings = 0,
                TotalEndings = 9,
                ArchiveCount = 8,
                TotalArchives = 19,
                SubplotCount = 0,
                TotalSubplots = 5
            };

            GlobalProgressModel mockModel = new GlobalProgressModel(mockDTO);
            GlobalProgressViewModel mockViewModel = new GlobalProgressViewModel(mockModel);

            Initialize(mockViewModel);
        }
    }

    public void Initialize(GlobalProgressViewModel viewModel)
    {
        if (viewModel == null)
        {
            return;
        }
        m_viewModel = viewModel;
        m_viewModel.OnStateChanged += UpdateVisuals;

        UpdateVisuals();
    }

    private void OnDestroy()
    {
        if (m_viewModel != null)
        {
            m_viewModel.OnStateChanged -= UpdateVisuals;
        }
    }

    private void UpdateVisuals()
    {
        if (m_viewModel == null)
        {
            return;
        }

        if (m_headerText != null)
        {
            m_headerText.text = m_viewModel.HeaderText;
        }
        if (m_playTimeText != null)
        {
            m_playTimeText.text = m_viewModel.PlayTimeText;
        }
        if (m_endingText != null)
        {
            m_endingText.text = m_viewModel.EndingText;
        }
        if (m_subplotText != null)
        {
            m_subplotText.text = m_viewModel.SubplotText;
        }
    }
}
